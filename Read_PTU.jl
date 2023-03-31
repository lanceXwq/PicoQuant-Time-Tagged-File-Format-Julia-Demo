using Printf
using Gtk
using Dates

# Read PicoQuant Unified TTTR Files
# This is demo code. Use at your own risk. No warranties.
# Marcus Sackrow, PicoQuant GmbH, December 2013
# Peter Kapusta, PicoQuant GmbH, November 2016
# Edited script: text output formatting changed by KAP.

# Note that marker events have a lower time resolution and may therefore appear
# in the file slightly out of order with respect to regular (photon) event records.
# This is by design. Markers are designed only for relatively coarse
# synchronization requirements such as image scanning.

# T Mode data are written to an output file [filename].out
# We do not keep it in memory because of the huge amout of memory
# this would take in case of large files. Of course you can change this,
# e.g. if your files are not too big.
# Otherwise it is best process the data on the fly and keep only the results.

# All HeaderData are introduced as Variable to Matlab and can directly be
# used for further analysis

# some constants
const tyEmpty8 = 0xFFFF0008
const tyBool8 = 0x00000008
const tyInt8 = 0x10000008
const tyBitSet64 = 0x11000008
const tyColor8 = 0x12000008
const tyFloat8 = 0x20000008
const tyTDateTime = 0x21000008
const tyFloat8Array = 0x2001FFFF
const tyAnsiString = 0x4001FFFF
const tyWideString = 0x4002FFFF
const tyBinaryBlob = 0xFFFFFFFF
# RecordTypes
const rtPicoHarpT3 = 0x00010303 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $03 (T3), HW: $03 (PicoHarp)
const rtPicoHarpT2 = 0x00010203 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $02 (T2), HW: $03 (PicoHarp)
const rtHydraHarpT3 = 0x00010304 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $03 (T3), HW: $04 (HydraHarp)
const rtHydraHarpT2 = 0x00010204 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $02 (T2), HW: $04 (HydraHarp)
const rtHydraHarp2T3 = 0x01010304 # (SubID = $01, RecFmt: $01) (V2), T-Mode: $03 (T3), HW: $04 (HydraHarp)
const rtHydraHarp2T2 = 0x01010204 # (SubID = $01, RecFmt: $01) (V2), T-Mode: $02 (T2), HW: $04 (HydraHarp)
const rtTimeHarp260NT3 = 0x00010305 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $03 (T3), HW: $05 (TimeHarp260N)
const rtTimeHarp260NT2 = 0x00010205 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $02 (T2), HW: $05 (TimeHarp260N)
const rtTimeHarp260PT3 = 0x00010306 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $03 (T3), HW: $06 (TimeHarp260P)
const rtTimeHarp260PT2 = 0x00010206 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $02 (T2), HW: $06 (TimeHarp260P)
const rtMultiHarpT3 = 0x00010307 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $03 (T3), HW: $07 (MultiHarp)
const rtMultiHarpT2 = 0x00010207 # (SubID = $00, RecFmt: $01) (V1), T-Mode: $02 (T2), HW: $07 (MultiHarp)

RecNum::Int = 0
cnt_ph::Int = 0
cnt_ov::Int = 0
cnt_ma::Int = 0

## Got Photon
#    TimeTag: Raw TimeTag from Record * Globalresolution = Real Time arrival of Photon
#    DTime: Arrival time of Photon after last Sync event (T3 only) DTime * Resolution = Real time arrival of Photon after last Sync event
#    Channel: Channel the Photon arrived (0 = Sync channel for T2 measurements)
function GotPhoton(TimeTag, Channel, DTime)
    global RecNum, cnt_ph
    cnt_ph += 1
    if (isT2)
        # Edited: formatting changed by PK
        @printf(
            fpout,
            "\n%10i CHN %i %18.0f (%0.1f ps)",
            RecNum,
            Channel,
            TimeTag,
            (TimeTag * tagdict["MeasDesc_GlobalResolution"] * 1e12)
        )
    else
        # Edited: formatting changed by PK
        @printf(
            fpout,
            "\n%10i CHN %i %18.0f (%0.1f ns) %ich",
            RecNum,
            Channel,
            TimeTag,
            (TimeTag * tagdict["MeasDesc_GlobalResolution"] * 1e9),
            DTime
        )
    end
end

## Got Marker
#    TimeTag: Raw TimeTag from Record * Globalresolution = Real Time arrival of Photon
#    Markers: Bitfield of arrived Markers, different markers can arrive at same time (same record)
function GotMarker(TimeTag, Markers)
    global RecNum, cnt_ma
    cnt_ma += 1
    # Edited: formatting changed by PK
    @printf(
        fpout,
        "\n%10i MAR %i %18.0f (%0.1f ns)",
        RecNum,
        Markers,
        TimeTag,
        (TimeTag * tagdict["MeasDesc_GlobalResolution"] * 1e9)
    )
end

## Got Overflow
#  Count: Some TCSPC provide Overflow compression = if no Photons between overflow you get one record for multiple Overflows
function GotOverflow(Count)
    global RecNum, cnt_ov
    cnt_ov += Count
    # Edited: formatting changed by PK
    @printf(fpout, "\n%10i OFL * %i", RecNum, Count)
end

## Decoder functions

## Read PicoHarp T3
function ReadPT3()
    global RecNum
    ofltime = 0
    WRAPAROUND = 65536

    for i = 1:tagdict["TTResult_NumberOfRecords"]
        RecNum = i
        T3Record = read(fid, UInt32)     # all 32 bits:
        #   +-------------------------------+  +-------------------------------+
        #   |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|  |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
        #   +-------------------------------+  +-------------------------------+
        nsync = (&)(T3Record, 65535)       # the lowest 16 bits:
        #   +-------------------------------+  +-------------------------------+
        #   | | | | | | | | | | | | | | | | |  |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
        #   +-------------------------------+  +-------------------------------+
        chan = (&)(>>>(T3Record, 28), 15)   # the upper 4 bits:
        #   +-------------------------------+  +-------------------------------+
        #   |x|x|x|x| | | | | | | | | | | | |  | | | | | | | | | | | | | | | | |
        #   +-------------------------------+  +-------------------------------+
        truensync = ofltime + nsync
        if (chan >= 1) && (chan <= 4)
            dtime = (&)(>>>(T3Record, 16), 4095)
            GotPhoton(truensync, chan, dtime)  # regular count at Ch1, Rt_Ch1 - Rt_Ch4 when the router is enabled
        elseif chan == 15 # special record
            markers = (&)(>>>(T3Record, 16), 15) # where these four bits are markers:
            #   +-------------------------------+  +-------------------------------+
            #   | | | | | | | | | | | | |x|x|x|x|  | | | | | | | | | | | | | | | | |
            #   +-------------------------------+  +-------------------------------+
            if markers == 0                           # then this is an overflow record
                ofltime = ofltime + WRAPAROUND         # and we unwrap the numsync (=time tag) overflow
                GotOverflow(1)
            else                                    # if nonzero, then this is a true marker event
                GotMarker(truensync, markers)
            end
        else
            @printf(fpout, "Err")
        end
    end
end

## Read PicoHarp T2
function ReadPT2()
    global RecNum
    ofltime = 0
    WRAPAROUND = 210698240

    for i = 1:tagdict["TTResult_NumberOfRecords"]
        RecNum = i
        T2Record = read(fid, UInt32)
        T2time = (&)(T2Record, 268435455)             #the lowest 28 bits
        chan = (&)(>>>(T2Record, 28), 15)      #the next 4 bits
        timetag = T2time + ofltime
        if (chan >= 0) && (chan <= 4)
            GotPhoton(timetag, chan, 0)
        elseif chan == 15
            markers = (&)(T2Record, 15)  # where the lowest 4 bits are marker bits
            if markers == 0                   # then this is an overflow record
                ofltime = ofltime + WRAPAROUND # and we unwrap the time tag overflow
                GotOverflow(1)
            else                            # otherwise it is a true marker
                GotMarker(timetag, markers)
            end
        else
            @printf(fpout, "Err")
        end
        # Strictly, in case of a marker, the lower 4 bits of time are invalid
        # because they carry the marker bits. So one could zero them out.
        # However, the marker resolution is only a few tens of nanoseconds anyway,
        # so we can just ignore the few picoseconds of error.
    end
end

## Read HydraHarp/TimeHarp260 T3
function ReadHT3(Version)
    global RecNum
    OverflowCorrection = 0
    T3WRAPAROUND = 1024

    for i = 1:tagdict["TTResult_NumberOfRecords"]
        RecNum = i
        T3Record = read(fid, UInt32)     # all 32 bits:
        #   +-------------------------------+  +-------------------------------+
        #   |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|  |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
        #   +-------------------------------+  +-------------------------------+
        nsync = (&)(T3Record, 1023)       # the lowest 10 bits:
        #   +-------------------------------+  +-------------------------------+
        #   | | | | | | | | | | | | | | | | |  | | | | | | |x|x|x|x|x|x|x|x|x|x|
        #   +-------------------------------+  +-------------------------------+
        dtime = (&)(>>>(T3Record, 10), 32767)   # the next 15 bits:
        #   the dtime unit depends on "Resolution" that can be obtained from header
        #   +-------------------------------+  +-------------------------------+
        #   | | | | | | | |x|x|x|x|x|x|x|x|x|  |x|x|x|x|x|x| | | | | | | | | | |
        #   +-------------------------------+  +-------------------------------+
        channel = (&)(>>>(T3Record, 25), 63)   # the next 6 bits:
        #   +-------------------------------+  +-------------------------------+
        #   | |x|x|x|x|x|x| | | | | | | | | |  | | | | | | | | | | | | | | | | |
        #   +-------------------------------+  +-------------------------------+
        special = (&)(>>>(T3Record, 31), 1)   # the last bit:
        #   +-------------------------------+  +-------------------------------+
        #   |x| | | | | | | | | | | | | | | |  | | | | | | | | | | | | | | | | |
        #   +-------------------------------+  +-------------------------------+
        if special == 0   # this means a regular input channel
            true_nSync = OverflowCorrection + nsync
            #  one nsync time unit equals to "syncperiod" which can be
            #  calculated from "SyncRate"
            GotPhoton(true_nSync, channel, dtime)
        elseif channel == 63  # overflow of nsync occured
            if (nsync == 0) || (Version == 1) # if nsync is zero it is an old style single oferflow or old Version
                OverflowCorrection = OverflowCorrection + T3WRAPAROUND
                GotOverflow(1)
            else         # otherwise nsync indicates the number of overflows - THIS IS NEW IN FORMAT V2.0
                OverflowCorrection = OverflowCorrection + T3WRAPAROUND * nsync
                GotOverflow(nsync)
            end
        elseif (channel >= 1) && (channel <= 15)  # these are markers
            true_nSync = OverflowCorrection + nsync
            GotMarker(true_nSync, channel)
        end
    end
end

## Read HydraHarp/TimeHarp260 T2
function ReadHT2(Version)
    global RecNum
    OverflowCorrection = 0
    T2WRAPAROUND_V1 = 33552000
    T2WRAPAROUND_V2 = 33554432 # = 2^25  IMPORTANT! THIS IS NEW IN FORMAT V2.0

    for i = 1:tagdict["TTResult_NumberOfRecords"]
        RecNum = i
        T2Record = read(fid, UInt32)     # all 32 bits:
        #   +-------------------------------+  +-------------------------------+
        #   |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|  |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
        #   +-------------------------------+  +-------------------------------+
        dtime = (&)(T2Record, 33554431)   # the last 25 bits:
        #   +-------------------------------+  +-------------------------------+
        #   | | | | | | | |x|x|x|x|x|x|x|x|x|  |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
        #   +-------------------------------+  +-------------------------------+
        channel = (&)(>>>(T2Record, 25), 63)   # the next 6 bits:
        #   +-------------------------------+  +-------------------------------+
        #   | |x|x|x|x|x|x| | | | | | | | | |  | | | | | | | | | | | | | | | | |
        #   +-------------------------------+  +-------------------------------+
        special = (&)(>>>(T2Record, 31), 1)   # the last bit:
        #   +-------------------------------+  +-------------------------------+
        #   |x| | | | | | | | | | | | | | | |  | | | | | | | | | | | | | | | | |
        #   +-------------------------------+  +-------------------------------+
        # the resolution in T2 mode is 1 ps  - IMPORTANT! THIS IS NEW IN FORMAT V2.0
        timetag = OverflowCorrection + dtime
        if special == 0   # this means a regular photon record
            GotPhoton(timetag, channel + 1, 0)
        elseif channel == 63  # overflow of dtime occured
            if Version == 1
                OverflowCorrection = OverflowCorrection + T2WRAPAROUND_V1
                GotOverflow(1)
            else
                if (dtime == 0) # if dtime is zero it is an old style single oferflow
                    OverflowCorrection = OverflowCorrection + T2WRAPAROUND_V2
                    GotOverflow(1)
                else         # otherwise dtime indicates the number of overflows - THIS IS NEW IN FORMAT V2.0
                    OverflowCorrection = OverflowCorrection + T2WRAPAROUND_V2 * dtime
                    GotOverflow(dtime)
                end
            end
        elseif channel == 0  # Sync event
            GotPhoton(timetag, channel, 0)
        elseif (channel >= 1) && (channel <= 15)  # these are markers
            GotMarker(timetag, channel)
        end
    end
end

# start Main program
fullpath =
    open_dialog("T-Mode data:", GtkNullContainer(), ("*.ptu",), select_multiple = false)
fid = open(fullpath, "r")

println("")
Magic = strip(String(read(fid, 8)), '\0')
Magic == "PQTTTR" || error("Magic invalid, this is not an PTU file.")
Version = strip(String(read(fid, 8)), '\0')
@printf("Tag Version: %s\n", Version)

# Instead of metaprogramming, dictionary is used here.
# Or it can be done via eval(Meta.parse("..."))
tagdict = Dict{String,Any}()
while true
    # read Tag Head
    TagIdent = strip(String(read(fid, 32)), '\0') # TagHead.Ident
    TagIdx = read(fid, Int32)    # TagHead.Idx
    TagTyp = read(fid, UInt32)   # TagHead.Typ
    # TagHead.Value will be read in the
    # right type function
    if TagIdx > -1
        EvalName = TagIdent * "(" * string(TagIdx + 1) * ")"
    else
        EvalName = TagIdent
    end
    @printf("\n   %-40s", EvalName)
    # check Typ of Header
    if TagTyp == tyEmpty8
        read(fid, Int)
        @printf("<Empty>")
        merge!(tagdict, Dict(EvalName => nothing))
    elseif TagTyp == tyBool8
        TagInt = read(fid, Int)
        if TagInt == 0
            @printf("FALSE")
            merge!(tagdict, Dict(EvalName => false))
        else
            @printf("TRUE")
            merge!(tagdict, Dict(EvalName => false))
        end
    elseif TagTyp == tyInt8
        TagInt = read(fid, Int)
        @printf("%d", TagInt)
        merge!(tagdict, Dict(EvalName => TagInt))
    elseif TagTyp == tyBitSet64
        TagInt = read(fid, Int)
        @printf("%X", TagInt)
        merge!(tagdict, Dict(EvalName => TagInt))
    elseif TagTyp == tyColor8
        TagInt = read(fid, Int)
        @printf("%X", TagInt)
        merge!(tagdict, Dict(EvalName => TagInt))
    elseif TagTyp == tyFloat8
        TagFloat = read(fid, Float64)
        @printf("%e", TagFloat)
        merge!(tagdict, Dict(EvalName => TagFloat))
    elseif TagTyp == tyFloat8Array
        TagInt = read(fid, Int)
        @printf("<Float array with #d Entries>", TagInt / 8)
        skip(fid, TagInt)
    elseif TagTyp == tyTDateTime
        TagFloat = read(fid, Float64)
        tagtime = Int(round((TagFloat - 25569) * 86400))
        tagtime = Dates.unix2datetime(tagtime) # TODO better datetime format
        @printf("%s", string(tagtime))
        merge!(tagdict, Dict(EvalName => tagtime))
    elseif TagTyp == tyAnsiString
        TagInt = read(fid, Int)
        TagString = strip(String(read(fid, TagInt)), '\0')
        @printf("%s", TagString)
        TagIdx > -1 && (EvalName = TagIdent * "{" * string(TagIdx + 1) * "}")
        merge!(tagdict, Dict(EvalName => TagString))
    elseif TagTyp == tyWideString
        # Read and remove the 0"s
        TagInt = read(fid, Int)
        TagString = strip(String(read(fid, TagInt)), '\0')
        @printf("%s", TagString)
        TagIdx > -1 && (EvalName = TagIdent * "{" * string(TagIdx + 1) * "}")
        merge!(tagdict, Dict(EvalName => TagString))
    elseif TagTyp == tyBinaryBlob
        TagInt = read(fid, Int)
        skip(fid, TagInt)
        merge!(tagdict, Dict(EvalName => TagInt))
    else
        error("Illegal Type identifier found! Broken file?")
    end
    TagIdent == "Header_End" && break
end
println("\n----------------------")
outfile = fullpath[1:end-4] * ".out"
fpout = open(outfile, "w")
# Check recordtype
if tagdict["TTResultFormat_TTTRRecType"] == rtPicoHarpT3
    isT2 = false
    println("PicoHarp T3 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtPicoHarpT2
    isT2 = true
    println("PicoHarp T2 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtHydraHarpT3
    isT2 = false
    println("HydraHarp V1 T3 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtHydraHarpT2
    isT2 = true
    println("HydraHarp V1 T2 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtHydraHarp2T3
    isT2 = false
    println("HydraHarp V2 T3 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtHydraHarp2T2
    isT2 = true
    println("HydraHarp V2 T2 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtTimeHarp260NT3
    isT2 = false
    println("TimeHarp260N T3 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtTimeHarp260NT2
    isT2 = true
    println("TimeHarp260N T2 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtTimeHarp260PT3
    isT2 = false
    println("TimeHarp260P T3 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtTimeHarp260PT2
    isT2 = true
    println("TimeHarp260P T2 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtMultiHarpT3
    isT2 = false
    println("MultiHarp T3 data")
elseif tagdict["TTResultFormat_TTTRRecType"] == rtMultiHarpT2
    isT2 = true
    println("MultiHarp T2 data")
else
    error("Illegal RecordType!")
end
@printf("\nWriting data to %s", outfile)
println("\nThis may take a while...")
# write Header
if (isT2)
    println(fpout, "  record# Type Ch        TimeTag             TrueTime/ps")
else
    println(
        fpout,
        "  record# Type Ch        TimeTag             TrueTime/ns            DTime",
    )
end

# choose right decode function
if tagdict["TTResultFormat_TTTRRecType"] == rtPicoHarpT3
    ReadPT3()
elseif tagdict["TTResultFormat_TTTRRecType"] == rtPicoHarpT2
    isT2 = true
    ReadPT2()
elseif tagdict["TTResultFormat_TTTRRecType"] == rtHydraHarpT3
    ReadHT3(1)
elseif tagdict["TTResultFormat_TTTRRecType"] == rtHydraHarpT2
    isT2 = true
    ReadHT2(1)
elseif tagdict["TTResultFormat_TTTRRecType"] in
       [rtMultiHarpT3, rtHydraHarp2T3, rtTimeHarp260NT3, rtTimeHarp260PT3]
    isT2 = false
    ReadHT3(2)
elseif tagdict["TTResultFormat_TTTRRecType"] in
       [rtMultiHarpT2, rtHydraHarp2T2, rtTimeHarp260NT2, rtTimeHarp260PT2]
    isT2 = true
    ReadHT2(2)
else
    error("Illegal RecordType!")
end
close(fid)
close(fpout)
println("Ready!\n")
println("\nStatistics obtained from the data:")
@printf("\n%i photons, %i overflows, %i markers.\n", cnt_ph, cnt_ov, cnt_ma)