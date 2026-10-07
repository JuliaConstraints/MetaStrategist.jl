export ParameterSpec, StrategyDescriptor, ExperimentGrammar, active_parameters, explain_configuration

"A parameter with a finite categorical domain or inclusive numeric bounds. Conditions are conjunctions."
struct ParameterSpec
    name::String
    kind::Symbol
    domain::Vector
    active_if::Dict{String,Any}
    function ParameterSpec(name, kind, domain; active_if=Dict())
        kind in (:categorical, :integer, :real) || throw(ArgumentError("unknown domain kind"))
        d = collect(domain)
        isempty(d) && throw(ArgumentError("empty domain"))
        kind == :categorical && length(unique(d)) != length(d) && throw(ArgumentError("duplicate categorical values"))
        if kind != :categorical
            length(d) == 2 && all(x -> x isa Real && isfinite(x), d) && d[1] <= d[2] ||
                throw(ArgumentError("numeric domains need finite ordered bounds"))
            kind == :integer && !all(x -> x isa Integer, d) && throw(ArgumentError("integer bounds required"))
            kind == :real && !all(x -> isfinite(Float64(x)), d) && throw(ArgumentError("real sampler requires finite Float64 bounds"))
        end
        new(string(name), kind, deepcopy(d), Dict(string(k)=>v for (k,v) in pairs(active_if)))
    end
end

struct StrategyDescriptor
    id::String
    implementation::String
    parameters::Vector{ParameterSpec}
    provides::Set{Symbol}
    requires::Set{Symbol}
    forbids::Set{Symbol}
    forbidden::Vector{Dict{String,Any}}
    provenance::Dict{String,Any}
    function StrategyDescriptor(id, implementation, parameters=ParameterSpec[];
            provides=(), requires=(), forbids=(), forbidden=[], provenance=Dict())
        seen = Set{String}()
        known = Dict{String,ParameterSpec}()
        for p in parameters
            p.name in seen && throw(ArgumentError("duplicate parameter $(p.name)"))
            all(k in seen for k in keys(p.active_if)) || throw(ArgumentError("conditions must reference earlier parameters"))
            all(in_domain(known[k],v) for (k,v) in p.active_if) || throw(ArgumentError("activation value outside parent domain"))
            push!(seen, p.name)
            known[p.name]=p
        end
        rules = [Dict{String,Any}(string(k)=>v for (k,v) in pairs(r)) for r in forbidden]
        all(!isempty(r) && all(k in seen for k in keys(r)) for r in rules) || throw(ArgumentError("invalid forbidden rule"))
        new(string(id), string(implementation), collect(parameters), Set(Symbol.(provides)),
            Set(Symbol.(requires)), Set(Symbol.(forbids)), rules,
            Dict{String,Any}(string(k)=>v for (k,v) in pairs(provenance)))
    end
end

struct ExperimentGrammar
    version::String
    strategies::Vector{StrategyDescriptor}
    capabilities::Set{Symbol}
    function ExperimentGrammar(version, strategies; capabilities=())
        isempty(strategies) && throw(ArgumentError("empty strategy catalog"))
        ids = getfield.(strategies, :id)
        length(unique(ids)) == length(ids) || throw(ArgumentError("duplicate strategy id"))
        new(string(version), collect(strategies), Set(Symbol.(capabilities)))
    end
end

matches(rule, values) = all(haskey(values,k) && isequal(values[k],v) for (k,v) in rule)
in_domain(p, v) = p.kind == :categorical ? any(isequal(v), p.domain) :
    v isa Real && isfinite(v) && (p.kind != :integer || v isa Integer) && p.domain[1] <= v <= p.domain[2]

function active_parameters(s::StrategyDescriptor, values)
    result = Dict{String,Any}()
    supplied = Dict(string(k)=>v for (k,v) in pairs(values))
    for p in s.parameters
        matches(p.active_if, result) || continue
        haskey(supplied,p.name) || throw(ArgumentError("missing active parameter $(p.name)"))
        in_domain(p, supplied[p.name]) || throw(ArgumentError("outside domain: $(p.name)"))
        result[p.name] = supplied[p.name]
    end
    all(k in getfield.(s.parameters,:name) for k in keys(supplied)) || throw(ArgumentError("unknown parameter"))
    result
end

function explain_configuration(g::ExperimentGrammar, id, values)
    i = findfirst(s -> s.id == string(id), g.strategies)
    i === nothing && return ["strategy absent from this epoch"]
    s = g.strategies[i]
    available = union(g.capabilities, s.provides)
    reasons = ["requires capability $c" for c in sort!(collect(setdiff(s.requires,available)))]
    append!(reasons, ["forbidden capability $c" for c in sort!(collect(intersect(s.forbids,available)))])
    active = try active_parameters(s, values) catch e
        e isa ArgumentError || rethrow()
        push!(reasons,sprint(showerror,e)); return reasons
    end
    for (i,r) in enumerate(s.forbidden)
        matches(r,active) && push!(reasons,"forbidden combination $i")
    end
    reasons
end
