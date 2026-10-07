"Cold source inventory. Paths are package-relative; this is evidence, not a native cache key."
function source_inventory(modules)
    Tuple(map(unique(collect(modules))) do m
        root=pkgdir(m)
        if root===nothing
            return (;module_name=string(m),version=nothing,status=:unknown,files=())
        end
        files=Pair{String,String}[]
        for part in ("src","ext")
            isdir(joinpath(root,part)) || continue
            for (dir,_,names) in walkdir(joinpath(root,part)), name in names
                endswith(name,".jl") || continue
                path=joinpath(dir,name)
                push!(files,replace(relpath(path,root),'\\'=>'/')=>bytes2hex(open(SHA.sha256,path)))
            end
        end
        sort!(files;by=first)
        (;module_name=string(m),version=string(pkgversion(m)),status=:source_inventory,
          files=Tuple((;path=first(p),sha256=last(p)) for p in files))
    end)
end

"Immutable cold receipt: bound configuration is distinct from observed adaptive events."
struct PreparationReceipt
    schema::String
    unit::String
    component::NamedTuple
    execution::NamedTuple
    model_revision::UInt64
    provenance::Tuple
    resources::NamedTuple
    identity::String
end
function preparation_receipt(;unit,component,execution,model_revision,provenance=(),resources=(;))
    description=(;schema="preparation-receipt/1",unit=string(unit),component,execution,model_revision,
        provenance=Tuple(provenance),resources)
    identity=bytes2hex(SHA.sha256(canonical_value(description)))
    PreparationReceipt(description.schema,string(unit),component,execution,UInt64(model_revision),
        Tuple(provenance),resources,identity)
end
receipt_snapshot(r::PreparationReceipt)=(;schema=r.schema,unit=r.unit,component=r.component,
    execution=r.execution,model_revision=r.model_revision,provenance=r.provenance,
    resources=r.resources,identity=r.identity)
export PreparationReceipt, preparation_receipt, receipt_snapshot, source_inventory

"Archive a receipt without overwriting history; exact scalars use the strategy codec."
function write_preparation_receipt(path::AbstractString,r::PreparationReceipt)
    target=abspath(path)
    length(target)<=240 || throw(ArgumentError("use a shorter receipt root"))
    ispath(target) && throw(ArgumentError("receipt already exists"))
    mkpath(dirname(target));tmp,io=mktemp(dirname(target))
    try
        length(tmp)<=240 || throw(ArgumentError("use a shorter temporary root"))
        snapshot=receipt_snapshot(r)
        TOML.print(io,Dict("schema"=>"preparation-receipt/1","receipt"=>_encode_strategy_value(snapshot));sorted=true)
        close(io)
        canonical_value(read_preparation_receipt(tmp))==canonical_value(snapshot) || error("receipt integrity check failed")
        mv(tmp,target;force=false)
    finally
        isopen(io) && close(io)
        isfile(tmp) && rm(tmp)
    end
    target
end
function read_preparation_receipt(path::AbstractString)
    record=TOML.parsefile(path)
    record["schema"]=="preparation-receipt/1" || throw(ArgumentError("unknown receipt schema"))
    r=_decode_strategy_value(record["receipt"])
    expected=preparation_receipt(;unit=r.unit,component=r.component,execution=r.execution,
        model_revision=r.model_revision,provenance=r.provenance,resources=r.resources)
    r.schema==expected.schema && r.identity==expected.identity || throw(ArgumentError("receipt integrity mismatch"))
    r
end
export write_preparation_receipt, read_preparation_receipt
