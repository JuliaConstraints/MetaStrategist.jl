function _encode_strategy_value(x)
    canonical_value(x)
    _encode_validated_strategy_value(x)
end

# The complete immutable value has already passed the portable-parameter validator.
# Recursive children need only be encoded; validating them again repeats subtree work.
function _encode_validated_strategy_value(x)
    if x isa NamedTuple
        names=sort!(collect(keys(x));by=string)
        return Dict("kind"=>"named","names"=>string.(names),"values"=>[_encode_validated_strategy_value(x[k]) for k in names])
    elseif x isa Tuple
        return Dict("kind"=>"tuple","values"=>[_encode_validated_strategy_value(v) for v in x])
    elseif x === nothing
        return Dict("kind"=>"nothing")
    elseif x isa Union{Float16,Float32,Float64}
        return Dict("kind"=>"float","type"=>string(typeof(x)),"bits"=>bitstring(x))
    elseif x isa Bool
        return Dict("kind"=>"bool","value"=>x)
    elseif x isa Integer
        return Dict("kind"=>"integer","type"=>string(typeof(x)),"value"=>string(x))
    end
    Dict("kind"=>x isa Symbol ? "symbol" : "string","value"=>string(x))
end
const _PORTABLE_INTEGER_TYPES=Dict(string(T)=>T for T in (Int8,Int16,Int32,Int64,Int128,UInt8,UInt16,UInt32,UInt64,UInt128))
function _decode_strategy_float(type::String,record)
    type=="Float16" && return reinterpret(Float16,parse(UInt16,record["bits"];base=2))
    type=="Float32" && return reinterpret(Float32,parse(UInt32,record["bits"];base=2))
    type=="Float64" && return reinterpret(Float64,parse(UInt64,record["bits"];base=2))
    throw(KeyError(type))
end
function _decode_strategy_float(type,record)
    T,U=Dict("Float16"=>(Float16,UInt16),"Float32"=>(Float32,UInt32),"Float64"=>(Float64,UInt64))[type]
    reinterpret(T,parse(U,record["bits"];base=2))
end
function _decode_strategy_value(x)
    kind=x["kind"]
    kind=="nothing" && return nothing
    kind=="bool" && return x["value"]::Bool
    kind=="symbol" && return Symbol(x["value"])
    kind=="string" && return x["value"]::String
    kind=="integer" && return parse(_PORTABLE_INTEGER_TYPES[x["type"]],x["value"])
    if kind=="float"
        return _decode_strategy_float(x["type"],x)
    end
    kind in ("tuple","named") || throw(ArgumentError("unknown snapshot type $kind"))
    values=Tuple(_decode_strategy_value(v) for v in x["values"])
    if kind=="named"
        names=Symbol.(x["names"])
        length(unique(names))==length(names) || throw(ArgumentError("duplicate snapshot key"))
        return NamedTuple{Tuple(names)}(values)
    end
    values
end
"Write an immutable, portable IR checkpoint; never overwrite an older checkpoint."
function write_strategy_snapshot(path::AbstractString,ir::ExecutionIR)
    target=abspath(path)
    length(target)<=240 || throw(ArgumentError("use a shorter checkpoint root"))
    ispath(target) && throw(ArgumentError("checkpoint already exists"))
    mkpath(dirname(target))
    temporary,io=mktemp(dirname(target))
    try
        length(temporary)<=240 || throw(ArgumentError("use a shorter temporary-file root"))
        snapshot=strategy_snapshot(ir)
        TOML.print(io,Dict("schema"=>"strategy-checkpoint/1","snapshot"=>_encode_strategy_value(snapshot));sorted=true)
        close(io)
        decoded=_decode_strategy_value(TOML.parsefile(temporary)["snapshot"])
        canonical_value(decoded)==canonical_value(snapshot) || error("snapshot verification failed")
        mv(temporary,target;force=false)
    finally
        isopen(io) && close(io)
        isfile(temporary) && rm(temporary)
    end
    target
end
function read_strategy_snapshot(path::AbstractString,catalog::PhaseCatalog)
    record=TOML.parsefile(path)
    record["schema"]=="strategy-checkpoint/1" || throw(ArgumentError("unknown checkpoint schema"))
    restore_strategy(catalog,_decode_strategy_value(record["snapshot"]))
end
export write_strategy_snapshot, read_strategy_snapshot
