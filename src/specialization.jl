"""Versioned choice. Parameters are portable values, never captured executable state."""
struct PhaseChoice
    implementation::Symbol
    version::String
    parameters::NamedTuple
end
function PhaseChoice(implementation::Symbol, version::AbstractString="1"; parameters...)
    p = _normalize_strategy_value((; parameters...))
    canonical_value(p) # reject unsupported/mutable parameter values at entry
    PhaseChoice(implementation, String(version), p)
end

"""Explicit removal; absence of an override means inheritance instead."""
struct SuppressPhase end

"""Cold registration. A factory receives (parameters, preparation_context) once per unit.
Effects describe resources in the execution context. An ordering must exist for every
read/write conflict; dependencies and before/after declarations establish that order.
"""
struct PhaseDefinition
    category::Symbol
    implementation::Symbol
    version::String
    factory::Any
    dependencies::Tuple
    before::Tuple
    after::Tuple
    reads::Tuple
    writes::Tuple
    invalidates::Tuple
    owns::Tuple
    requires::Tuple
    provides::Tuple
end
function PhaseDefinition(category::Symbol, implementation::Symbol, factory;
        version="1", dependencies=(), before=(), after=(), reads=(), writes=(),
        invalidates=(), owns=(), requires=(), provides=())
    lists = map((dependencies,before,after,reads,writes,invalidates,owns,requires,provides)) do xs
        Tuple(sort!(unique!(Symbol[xs...]); by=string))
    end
    PhaseDefinition(category,implementation,String(version),factory,lists...)
end

struct PhaseCatalog
    definitions::Dict{Tuple{Symbol,Symbol,String},PhaseDefinition}
end
PhaseCatalog() = PhaseCatalog(Dict{Tuple{Symbol,Symbol,String},PhaseDefinition}())
function register_phase!(catalog::PhaseCatalog, phase::PhaseDefinition)
    key=(phase.category,phase.implementation,phase.version)
    haskey(catalog.definitions,key) && throw(ArgumentError("duplicate phase registration $key"))
    catalog.definitions[key]=phase
    catalog
end

struct StrategyProfile
    id::Symbol
    version::String
    defaults::Dict{Symbol,PhaseChoice}
end
StrategyProfile(id::Symbol, version::AbstractString, defaults) =
    StrategyProfile(id,String(version),Dict{Symbol,PhaseChoice}(defaults))

struct ResolvedPhase
    definition::PhaseDefinition
    choice::PhaseChoice
end
"Cold resolved description. Never pass this object into the hot loop."
struct ExecutionIR
    phases::Vector{ResolvedPhase}
    inputs::Tuple
    capabilities::Tuple
    semantic_key::String
    shape_key::String
end

# Explicit type tags and exact float bits. This is an identity encoding, not Julia display.
function canonical_value(x)
    Base.@nospecialize x
    io=IOBuffer()
    _write_canonical_value(io,x)
    String(take!(io))
end

# Identity encoding is cold and value-driven. Stream into one buffer instead of
# specializing recursive string joins for every nested strategy/receipt tuple.
function _write_decimal_length(io::IO,count::Int)
    count>=10 && _write_decimal_length(io,count÷10)
    write(io,UInt8(48+count%10))
    nothing
end
function _write_canonical_value(io::IO,x)
    Base.@nospecialize x
    if x === nothing
        write(io,"n;")
    elseif x isa Bool
        write(io,x ? "b1;" : "b0;")
    elseif x isa Symbol
        write(io,"y")
        _write_canonical_value(io,string(x))
    elseif x isa String
        (startswith(x,"/") || startswith(x,"\\\\") || occursin(r"^[A-Za-z]:[/\\]",x)) &&
            throw(ArgumentError("absolute paths are not portable strategy parameters"))
        write(io,UInt8(115))
        _write_decimal_length(io,ncodeunits(x))
        write(io,UInt8(58))
        write(io,x)
    elseif x isa Integer && isbitstype(typeof(x))
        print(io,"i",typeof(x),":",x,";")
    elseif x isa Union{Float16,Float32,Float64}
        print(io,"f",sizeof(x),":",bitstring(x),";")
    elseif x isa NamedTuple
        # Symbols and their String names use the same byte-lexical ordering.
        keys_sorted=sort!(collect(keys(x)))
        write(io,"m")
        for key in keys_sorted
            _write_canonical_value(io,key)
            _write_canonical_value(io,x[key])
        end
        write(io,";")
    elseif x isa Tuple
        write(io,"t")
        for value in x
            _write_canonical_value(io,value)
        end
        write(io,";")
    else
        throw(ArgumentError("non-portable strategy parameter $(typeof(x)); use immutable scalar/tuple values"))
    end
    nothing
end
_parameter_shape(x::NamedTuple) = NamedTuple{Tuple(sort!(collect(keys(x));by=string))}(
    Tuple(_parameter_shape(x[k]) for k in sort!(collect(keys(x));by=string)))
_parameter_shape(x::Tuple) = map(_parameter_shape,x)
_normalize_strategy_value(x::Tuple)=map(_normalize_strategy_value,x)
_normalize_strategy_value(x)=x
function _normalize_strategy_value(x::NamedTuple)
    names=Tuple(sort!(collect(keys(x));by=string))
    NamedTuple{names}(Tuple(_normalize_strategy_value(x[k]) for k in names))
end

_parameter_shape(x) = string(typeof(x))
function _phase_description(p::ResolvedPhase; shape=false)
    d=p.definition
    (; category=d.category, implementation=d.implementation, version=d.version,
       parameters=shape ? _parameter_shape(p.choice.parameters) : p.choice.parameters,
       dependencies=d.dependencies,before=d.before,after=d.after,reads=d.reads,
       writes=d.writes,invalidates=d.invalidates,owns=d.owns,requires=d.requires,provides=d.provides)
end
_ir_key(phases, inputs, capabilities; shape=false) = bytes2hex(SHA.sha256(canonical_value(
    (; schema="strategy-ir/1",phases=Tuple(_phase_description(p;shape) for p in phases),inputs,capabilities))))

"""Resolve only the roots' closure. Reject suppressed dependencies, cycles, unordered
effects, missing resources/capabilities and multiple owners with actionable phase names.
"""
function resolve_strategy(catalog::PhaseCatalog, profile::StrategyProfile;
        roots, overrides=(), inputs=(), capabilities=())
    chosen=copy(profile.defaults)
    seen=Set{Symbol}()
    for (role,value) in (overrides isa NamedTuple || overrides isa AbstractDict ? pairs(overrides) : overrides)
        role=Symbol(role)
        role in seen && throw(ArgumentError("duplicate override $role"))
        push!(seen,role)
        any(k->first(k)==role, keys(catalog.definitions)) || throw(ArgumentError("unknown category $role"))
        if value isa SuppressPhase
            delete!(chosen,role)
        elseif value isa PhaseChoice
            chosen[role]=value
        else
            throw(ArgumentError("override $role needs PhaseChoice or SuppressPhase"))
        end
    end
    active=Dict{Symbol,ResolvedPhase}(); visiting=Symbol[]
    function visit(role)
        role in visiting && throw(ArgumentError("dependency cycle: $(join((visiting...,role), " -> "))"))
        haskey(active,role) && return
        haskey(chosen,role) || throw(ArgumentError("missing or suppressed phase $role required by $(join(visiting," -> "))"))
        c=chosen[role]; key=(role,c.implementation,c.version)
        haskey(catalog.definitions,key) || throw(ArgumentError("unregistered implementation $key"))
        d=catalog.definitions[key]
        push!(visiting,role)
        foreach(visit,d.dependencies)
        pop!(visiting)
        active[role]=ResolvedPhase(d,c)
    end
    foreach(visit,Symbol.(collect(roots)))
    isempty(active) && throw(ArgumentError("no active phases"))
    roles=sort!(collect(keys(active));by=string)
    edges=Dict(r=>Set{Symbol}() for r in roles)
    for r in roles
        d=active[r].definition
        for prior in (d.dependencies..., d.after...)
            haskey(active,prior) && push!(edges[prior],r)
        end
        for later in d.before
            haskey(active,later) && push!(edges[r],later)
        end
    end
    incoming=Dict(r=>0 for r in roles)
    for successors in values(edges), successor in successors
        incoming[successor]+=1
    end
    order=Symbol[]; pending=Set(roles)
    ready=filter(r->iszero(incoming[r]),roles)
    while !isempty(pending)
        isempty(ready) && throw(ArgumentError("phase ordering cycle among $(sort!(collect(pending);by=string))"))
        append!(order,ready); setdiff!(pending,ready)
        # Finish the entire ready batch before collecting its successors, so
        # independent phases retain the original lexical batch ordering.
        next_ready=Symbol[]
        for role in ready, successor in edges[role]
            incoming[successor]-=1
            iszero(incoming[successor]) && push!(next_ready,successor)
        end
        ready=sort!(next_ready;by=string)
    end
    # Reuse the DAG closure for every effect pair instead of allocating a DFS
    # traversal per pair. The order above is already proven acyclic.
    reachable=Dict(r=>copy(edges[r]) for r in roles)
    for r in reverse(order)
        for successor in edges[r]
            union!(reachable[r],reachable[successor])
        end
    end
    mutations=Dict(r=>Set((active[r].definition.writes...,active[r].definition.invalidates...)) for r in roles)
    readsets=Dict(r=>Set(active[r].definition.reads) for r in roles)
    accesses=Dict(r=>union(mutations[r],readsets[r]) for r in roles)
    owners=Dict{Symbol,Symbol}()
    for (i,a) in pairs(roles)
        da=active[a].definition
        for owned in da.owns
            haskey(owners,owned) && throw(ArgumentError("resource $owned owned by $(owners[owned]) and $a"))
            owners[owned]=a
        end
        for b in roles[i+1:end]
            conflict=!isdisjoint(mutations[a],accesses[b]) || !isdisjoint(mutations[b],readsets[a])
            conflict && !(b in reachable[a]) && !(a in reachable[b]) &&
                throw(ArgumentError("unordered resource effects between $a and $b; declare before/after"))
        end
    end
    available=Set{Symbol}(inputs); caps=Set{Symbol}(capabilities)
    phases=ResolvedPhase[active[r] for r in order]
    for p in phases
        d=p.definition
        issubset(Set(d.reads),available) || throw(ArgumentError("missing/invalid resources for $(d.category): $(setdiff(Set(d.reads),available))"))
        issubset(Set(d.requires),caps) || throw(ArgumentError("missing capabilities for $(d.category): $(setdiff(Set(d.requires),caps))"))
        setdiff!(available,d.invalidates); union!(available,d.writes); union!(caps,d.provides)
    end
    ins=Tuple(sort!(unique!(Symbol[inputs...]);by=string))
    cs=Tuple(sort!(unique!(Symbol[capabilities...]);by=string))
    ExecutionIR(phases,ins,cs,_ir_key(phases,ins,cs),_ir_key(phases,ins,cs;shape=true))
end

"Portable immutable snapshot: re-resolve against exact implementation versions on restore."
strategy_snapshot(ir::ExecutionIR) = (;schema="strategy-ir/1",key=ir.semantic_key,
    inputs=ir.inputs,capabilities=ir.capabilities,
    phases=Tuple(_phase_description(p) for p in ir.phases))
"Explain active bindings and explicit suppression without adding work to execution."
function explain_strategy(catalog::PhaseCatalog,profile::StrategyProfile;roots,overrides=(),kwargs...)
    ir=resolve_strategy(catalog,profile;roots,overrides,kwargs...)
    edits=Dict(overrides isa NamedTuple || overrides isa AbstractDict ? pairs(overrides) : overrides)
    active=Set(p.definition.category for p in ir.phases)
    categories=sort!(unique!(Symbol[first(k) for k in keys(catalog.definitions)]);by=string)
    (;plan=strategy_snapshot(ir),profile=(;name=profile.id,version=profile.version),
      exclusions=Tuple((;category=c,reason=get(edits,c,nothing) isa SuppressPhase ? :explicitly_suppressed : :outside_active_closure)
          for c in categories if !(c in active)))
end
export explain_strategy
function restore_strategy(catalog::PhaseCatalog,snapshot)
    snapshot.schema=="strategy-ir/1" || throw(ArgumentError("unsupported strategy schema"))
    defaults=Dict(p.category=>PhaseChoice(p.implementation,p.version;p.parameters...) for p in snapshot.phases)
    ir=resolve_strategy(catalog,StrategyProfile(:restored,"1",defaults);
        roots=Tuple(p.category for p in snapshot.phases),inputs=snapshot.inputs,capabilities=snapshot.capabilities)
    ir.semantic_key==snapshot.key || throw(ArgumentError("strategy dependencies/effects changed since snapshot"))
    ir
end

struct PhaseSegment{P<:Tuple}
    phases::P
end
struct SpecializedKernel{S<:Tuple}
    segments::S
end
struct ReferenceKernel
    phases::Vector{Any}
end
"Ordinary Julia realization with concrete active phases; no generated functions."
struct TypedKernel{P<:Tuple}
    phases::P
end
@inline function execute!(k::TypedKernel, context)
    foreach(p -> p(context), k.phases)
    nothing
end
"Execute without the cold plan; a phase mutates its explicit context and returns nothing."
function execute!(k::ReferenceKernel, context)
    for phase in k.phases
        phase(context)
    end
    nothing
end
@inline @generated function execute!(k::PhaseSegment{P}, context) where P
    Expr(:block, [:(getfield(k.phases,$i)(context)) for i in 1:fieldcount(P)]..., :(nothing))
end
@inline @generated function execute!(k::SpecializedKernel{S}, context) where S
    Expr(:block, [:(execute!(getfield(k.segments,$i),context)) for i in 1:fieldcount(S)]..., :(nothing))
end

"Single-coordinator budget. Never reset in a live worker to claim native code was freed."
mutable struct GenerationBudget
    max_variants::Int
    max_phases::Int
    segment_size::Int
    variants::Set{Any}
    recycle_requested::Bool
    identity::String
    owner::Int
    lock::ReentrantLock
    admitted_shapes::Set{String}
    preparations::Int
    fallbacks::Int
    factory_ns::UInt64
end
function GenerationBudget(;max_variants=64,max_phases=128,segment_size=16)
    max_variants>=0 && max_phases>0 && 1<=segment_size<=32 || throw(ArgumentError("invalid generation limits"))
    GenerationBudget(max_variants,max_phases,segment_size,Set{Any}(),false,
        string(getpid(),'-',time_ns()),getpid(),ReentrantLock(),Set{String}(),0,0,0)
end
const _preparation_services = Dict{String,GenerationBudget}()
const _preparation_services_lock = ReentrantLock()
const _default_preparation_service=Ref{Union{Nothing,GenerationBudget}}(nothing)
function default_preparation_service()
    lock(_preparation_services_lock) do
        b=_default_preparation_service[]
        if b===nothing || b.owner!=getpid()
            b=GenerationBudget();_default_preparation_service[]=b
        end
        preparation_service(b)
    end
end
"Copies share admission within a process. Deserialized budgets bind to a fresh local service."
function preparation_service(b::GenerationBudget)
    lock(_preparation_services_lock) do
        haskey(_preparation_services,b.identity) && return _preparation_services[b.identity]
        local_budget = b.owner==getpid() ? b : GenerationBudget(
            max_variants=b.max_variants,max_phases=b.max_phases,segment_size=b.segment_size)
        local_budget.identity=b.identity
        # Admission history lives until process exit, just like compiled methods.
        # GC of a builder must not silently reset a previously spent quota.
        _preparation_services[b.identity]=local_budget
        local_budget
    end
end
function Base.deepcopy_internal(b::GenerationBudget, stackdict::IdDict)
    result=preparation_service(b)
    stackdict[b]=result
    result
end
function preparation_statistics(b::GenerationBudget)
    b=preparation_service(b)
    lock(b.lock) do
        (;process=b.owner,service=b.identity,variants=length(b.variants),
          preparations=b.preparations,fallbacks=b.fallbacks,factory_ns=b.factory_ns,
          recycle_requested=b.recycle_requested)
    end
end
struct PreparedStrategy{K}
    kernel::K
    semantic_key::String
    shape_key::String
    mode::Symbol
    reason::String
end
"Factories own their captures. Clone the entire resulting graph, never phases separately."
clone_kernel(k) = deepcopy(k)
struct PhaseFactory{F,P}
    factory::F
    parameters::P
end
(f::PhaseFactory)(context)=f.factory(f.parameters,context)
"A cold reusable factory plan. No catalogue traversal or fingerprinting per trajectory."
struct StrategyTemplate{F}
    factories::F
    semantic_key::String
    shape_key::String
    snapshot::NamedTuple
end
function strategy_template(ir::ExecutionIR)
    _ir_key(ir.phases,ir.inputs,ir.capabilities)==ir.semantic_key || throw(ArgumentError("IR mutated after resolution"))
    factories=Any[PhaseFactory(p.definition.factory,p.choice.parameters) for p in ir.phases]
    # Avoid creating a giant typed tuple even when the caller requests a reference path.
    bounded=length(factories)<=128 ? Tuple(factories) : factories
    StrategyTemplate(bounded,ir.semantic_key,ir.shape_key,strategy_snapshot(ir))
end
function prepare_strategy(ir::ExecutionIR, context=nothing;kwargs...)
    instantiate_strategy(strategy_template(ir),context;kwargs...)
end
function instantiate_strategy(template::StrategyTemplate, context=nothing;
        budget=GenerationBudget(),mode=:generated,execution_type=Nothing)
    mode in (:generated,:typed,:reference) || throw(ArgumentError("unknown realization $mode"))
    budget=preparation_service(budget)
    lock(budget.lock) do
        budget.preparations+=1
        selected=mode
        reason="explicit $mode realization"
        if selected!=:reference && (length(template.factories)>budget.max_phases || !(template.factories isa Tuple))
            selected=:reference; reason="active phase limit exceeded"
        elseif selected!=:reference && !(template.shape_key in budget.admitted_shapes) && length(budget.variants)>=budget.max_variants
            selected=:reference; reason="process admission quota exhausted before factories; recycle at checkpoint"
            budget.recycle_requested=true
        end
        started=time_ns()
        # Reference still needs its components, but avoids constructing a giant typed tuple.
        phases=try
            selected==:reference ? _reference_phases(template.factories,context) : map(f->f(context),template.factories)
        finally
            budget.factory_ns+=time_ns()-started
        end
        # Preparation-only labels are excluded. Supply the actual hot argument type when relevant.
        signature=(template.shape_key,execution_type,typeof(phases),selected)
        if selected!=:reference && !(signature in budget.variants) && length(budget.variants)>=budget.max_variants
            selected=:reference; reason="actual phase type quota exhausted; recycle at checkpoint"
            budget.recycle_requested=true
        end
        kernel=if selected==:reference
            budget.fallbacks+=mode==:reference ? 0 : 1
            # The reference factory path already returns a fresh owned vector.
            # An actual-type quota fallback still arrives with a typed tuple.
            ReferenceKernel(phases isa Vector{Any} ? phases : Any[phases...])
        else
            push!(budget.variants,signature); push!(budget.admitted_shapes,template.shape_key)
            selected==:typed ? TypedKernel(phases) :
                SpecializedKernel(Tuple(PhaseSegment(phases[i:min(i+budget.segment_size-1,end)])
                    for i in 1:budget.segment_size:length(phases)))
        end
        PreparedStrategy(kernel,template.semantic_key,template.shape_key,selected,reason)
    end
end
function _reference_phases(factories,context)
    Base.@nospecialize factories context
    Any[f(context) for f in factories]
end
export strategy_template, instantiate_strategy, TypedKernel, preparation_service, preparation_statistics, default_preparation_service
