using Printf

RecNum = 0
cnt_ph = 0
cnt_ov = 0
cnt_ma = 0

## Got Photon
#    TimeTag: Raw TimeTag from Record * Globalresolution = Real Time arrival of Photon
#    DTime: Arrival time of Photon after last Sync event (T3 only) DTime * Resolution = Real time arrival of Photon after last Sync event
#    Channel: Channel the Photon arrived (0 = Sync channel for T2 measurements)
function GotPhoton(TimeTag, Channel, DTime, cnt_ph)
    cnt_ph += 1

    # Edited: formatting changed by PK
    #=@printf(
        #fpout,
        "\n#10i CHN #i #18.0f (#0.1f ns) #ich",
        #RecNum,
        Channel,
        TimeTag,
        (TimeTag * Resolution * 1e9),
        DTime
    )=#
end

## Got Marker
#    TimeTag: Raw TimeTag from Record * Globalresolution = Real Time arrival of Photon
#    Markers: Bitfield of arrived Markers, different markers can arrive at same time (same record)
function GotMarker(TimeTag, Markers, cnt_ma)
    cnt_ma += 1
    # Edited: formatting changed by PK
    #=@printf(
        #fpout,
        "\n#10i MAR #i #18.0f (#0.1f ns)",
        #RecNum,
        Markers,
        TimeTag,
        (TimeTag * Resolution * 1e9)
    )=#
end

## Got Overflow
#  Count: Some TCSPC provide Overflow compression = if no Photons between overflow you get one record for multiple Overflows
function GotOverflow(Count, cnt_ov)
    cnt_ov += Count
    # Edited: formatting changed by PK
    #=@printf(#fpout, 
    "\n#10i OFL * #i", 
    #RecNum, 
    Count)=#
end

## Read HydraHarp/TimeHarp260 T3
function ReadHT3(Version, cnt_ph, cnt_ov, cnt_ma)
    OverflowCorrection = 0
    T3WRAPAROUND = 1024

    for i = 1:nRecords
        RecNum = i
        T3Record = read(fid, UInt32)     # all 32 bits:
        #   +-------------------------------+  +-------------------------------+
        #   |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|  |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
        #   +-------------------------------+  +-------------------------------+
        nsync = T3Record & 1023       # the lowest 10 bits:
        #   +-------------------------------+  +-------------------------------+
        #   | | | | | | | | | | | | | | | | |  | | | | | | |x|x|x|x|x|x|x|x|x|x|
        #   +-------------------------------+  +-------------------------------+
        dtime = (T3Record >>> 10) & 32767   # the next 15 bits:
        #   the dtime unit depends on "Resolution" that can be obtained from header
        #   +-------------------------------+  +-------------------------------+
        #   | | | | | | | |x|x|x|x|x|x|x|x|x|  |x|x|x|x|x|x| | | | | | | | | | |
        #   +-------------------------------+  +-------------------------------+
        channel = (T3Record >>> 25) & 63   # the next 6 bits:
        #   +-------------------------------+  +-------------------------------+
        #   | |x|x|x|x|x|x| | | | | | | | | |  | | | | | | | | | | | | | | | | |
        #   +-------------------------------+  +-------------------------------+
        special = (T3Record >>> 31) & 1   # the last bit:
        #   +-------------------------------+  +-------------------------------+
        #   |x| | | | | | | | | | | | | | | |  | | | | | | | | | | | | | | | | |
        #   +-------------------------------+  +-------------------------------+
        if special == 0   # this means a regular input channel
            true_nSync = OverflowCorrection + nsync
            #  one nsync time unit equals to "syncperiod" which can be
            #  calculated from "SyncRate"
            GotPhoton(true_nSync, channel, dtime, cnt_ph)
        elseif channel == 63  # overflow of nsync occured
            if (nsync == 0) || (Version == 1) # if nsync is zero it is an old style single oferflow or old Version
                OverflowCorrection = OverflowCorrection + T3WRAPAROUND
                GotOverflow(1, cnt_ov)
            else         # otherwise nsync indicates the number of overflows - THIS IS NEW IN FORMAT V2.0
                OverflowCorrection = OverflowCorrection + T3WRAPAROUND * nsync
                GotOverflow(nsync, cnt_ov)
            end
        elseif (channel >= 1) && (channel <= 15)  # these are markers
            true_nSync = OverflowCorrection + nsync
            GotMarker(true_nSync, channel, cnt_ma)
        end
    end
end


# TODO add more support as PAM 
##################################################################################
#
# ASCII file header
#
##################################################################################
fid = open("../../../data sets/enderlein/EGFP_raw/Point_3.ht3", "r")
fpout = open("../../../data sets/enderlein/EGFP_raw/Point_3.jlout", "w")
Ident = strip(String(read(fid, 16)), '\0')
FormatVersion = strip(String(read(fid, 6)), '\0')

if FormatVersion == "1.0"
    Version = 1
elseif FormatVersion == "2.0"
    Version = 2
end

CreatorName = strip(String(read(fid, 18)), '\0')
CreatorVersion = strip(String(read(fid, 12)), '\0')
FileTime = strip(String(read(fid, 18)), '\0')
CRLF = strip(String(read(fid, 2)), '\0') # TODO check the meaning of this variable
Comment = strip(String(read(fid, 256)), '\0')

##################################################################################
#
# Binary file header
#
##################################################################################

# The binary file header information is indentical to that in HHD files.
# Note that some items are not meaningful in the time tagging modes
# therefore we do not output them.

NumberOfCurves = read(fid, Int32)
BitsPerRecord = read(fid, Int32)
ActiveCurve = read(fid, Int32)
MeasurementMode = read(fid, Int32)
SubMode = read(fid, Int32)
Binning = read(fid, Int32)
Resolution = read(fid, Float64)

#Header.Resolution = Resolution

Offset = read(fid, Int32)
Tacq = read(fid, Int32)

StopAt = read(fid, UInt32)
StopOnOvfl = read(fid, Int32)
Restart = read(fid, Int32)
DispLinLog = read(fid, Int32)
DispTimeAxisFrom = read(fid, Int32)
DispTimeAxisTo = read(fid, Int32)
DispCountAxisFrom = read(fid, Int32)
DispCountAxisTo = read(fid, Int32)

##################################################################################

DispCurveMapTo = Vector{Int32}(undef, 8)
DispCurveShow = Vector{Int32}(undef, 8)
for i = 1:8
    DispCurveMapTo[i] = read(fid, Int32)
    DispCurveShow[i] = read(fid, Int32)
end

##################################################################################

ParamStart = Vector{Float32}(undef, 3)
ParamStep = Vector{Float32}(undef, 3)
ParamEnd = Vector{Float32}(undef, 3)
for i = 1:3
    ParamStart[i] = read(fid, Float32)
    ParamStep[i] = read(fid, Float32)
    ParamEnd[i] = read(fid, Float32)
end

##################################################################################

RepeatMode = read(fid, Int32)
RepeatsPerCurve = read(fid, Int32)
RepatTime = read(fid, Int32)
RepeatWaitTime = read(fid, Int32)
ScriptName = String(read(fid, 20)) # TODO deblank?

##################################################################################
#
#          Hardware information header
#
##################################################################################

HardwareIdent = String(read(fid, 16))
HardwarePartNo = String(read(fid, 8))
HardwareSerial = read(fid, Int32)
nModulesPresent = read(fid, Int32)

ModelCode = Vector{Int32}(undef, 10)
VersionCode = Vector{Int32}(undef, 10)
for i = 1:10
    ModelCode[i] = read(fid, Int32)
    VersionCode[i] = read(fid, Int32)
end

BaseResolution = read(fid, Float64)
InputsEnabled = read(fid, UInt64) # TODO check this part
InpChansPresent = read(fid, Int32)
RefClockSource = read(fid, Int32)
ExtDevices = read(fid, Int32)
MarkerSettings = read(fid, Int32)

SyncDivider = read(fid, Int32)
SyncCFDLevel = read(fid, Int32)
SyncCFDZeroCross = read(fid, Int32)
SyncOffset = read(fid, Int32)

##################################################################################
#
#          Channels' information header
#
##################################################################################

InputModuleIndex = Vector{Int32}(undef, InpChansPresent)
InputCFDLevel = Vector{Int32}(undef, InpChansPresent)
InputCFDZeroCross = Vector{Int32}(undef, InpChansPresent)
InputOffset = Vector{Int32}(undef, InpChansPresent)
for i = 1:InpChansPresent
    InputModuleIndex[i] = read(fid, Int32)
    InputCFDLevel[i] = read(fid, Int32)
    InputCFDZeroCross[i] = read(fid, Int32)
    InputOffset[i] = read(fid, Int32)
end



##################################################################################
#
#                Time tagging mode specific header
#
##################################################################################

InputRate = Vector{Int32}(undef, InpChansPresent)
for i = 1:InpChansPresent
    InputRate[i] = read(fid, Int32)
end

SyncRate = read(fid, Int32)

#Header.SyncRate = double(SyncRate)
#Header.ClockRate = Header.SyncRate # the MT clock is the syncrate

StopAfter = read(fid, Int32)

StopReason = read(fid, Int32)

ImgHdrSize = read(fid, Int32)

test1 = read(fid, 8)
#test2 = read(fid, Int32)

# nRecords = read(fid, UInt64) # ! This line is problematic, it seems that only the last 32 bits are useful.
nRecords = -(mark(fid) - position(seekend(fid))) / 4
isinteger(nRecords) || @warn "Number of records is not an integer!"

# Special header for imaging. How many of the following ImgHdr array elements
# are actually present in the file is indicated by ImgHdrSize above.
# Storage must be allocated dynamically if ImgHdrSize other than 0 is found.

#ImgHdr = read(fid, ImgHdrSize, 'int32')  # You have to properly interpret ImgHdr if you want to generate an image


# The header section end after ImgHdr. Following in the file are only event records.
# How many of them actually are in the file is indicated by nRecords in above.


##############################################################################
#
#  This reads the T3 mode event records
#
##############################################################################

# The macrotime clock rate is the syncrate.
syncperiod = 1E9 / SyncRate      # in nanoseconds

OverflowCorrection = 0
T3WRAPAROUND = 1024

ReadHT3(Version, cnt_ph, cnt_ov, cnt_ma)

