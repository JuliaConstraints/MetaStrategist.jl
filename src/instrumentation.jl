function literal_events(events)
    events isa Expr && events.head === :tuple ||
        throw(ArgumentError("instrumentation requires a literal tuple of events"))
    all(e -> e isa QuoteNode && e.value isa Symbol, events.args) ||
        throw(ArgumentError("instrumentation events must be literal symbols"))
    names = Symbol[e.value for e in events.args]
    length(unique(names)) == length(names) || throw(ArgumentError("duplicate event"))
    return Set(names)
end

# Recognize this module's qualified marker; do not remove a foreign homonym.
function own_marker(x, caller)
    x isa GlobalRef && return x.mod === MetaStrategist && x.name === Symbol("@telemetry")
    if x isa Symbol
        return isdefined(caller,x) && getfield(caller,x) === var"@telemetry"
    end
    if x isa Expr && x.head === :. && length(x.args)==2 && x.args[1] isa Symbol
        owner=x.args[1]
        return isdefined(caller,owner) && getfield(caller,owner) === MetaStrategist &&
            x.args[2] isa QuoteNode && x.args[2].value===Symbol("@telemetry")
    end
    false
end

function contains_marker(x, caller)
    x isa QuoteNode && return false
    x isa Expr || return false
    x.head === :quote && return false
    x.head === :macrocall && own_marker(x.args[1], caller) && return true
    any(a->contains_marker(a,caller), x.args)
end

function reject_control_transfer(x)
    x isa QuoteNode && return
    x isa Expr || return
    x.head in (:quote, :function, :(->)) && return
    x.head in (:return, :break, :continue) &&
        throw(ArgumentError("telemetry may not transfer algorithmic control"))
    foreach(reject_control_transfer, x.args)
end

function filter_body(x, enabled; statement=false, caller=@__MODULE__)
    x isa Expr || return x
    x.head === :quote && return x
    if x.head === :macrocall
        if own_marker(x.args[1], caller)
            statement || throw(ArgumentError("telemetry must be a statement"))
            length(x.args) == 4 || throw(ArgumentError("expected event and one body"))
            event = x.args[3]
            event isa QuoteNode && event.value isa Symbol ||
                throw(ArgumentError("event must be a literal symbol"))
            reject_control_transfer(x.args[4])
            event.value in enabled || return nothing
            return Expr(:block, x.args[2], filter_body(x.args[4], enabled; statement=true,caller), nothing)
        end
        contains_marker(x,caller) && throw(ArgumentError("marker hidden inside an unknown macro"))
        return x
    end
    if x.head in (:function, :(->))
        contains_marker(x,caller) && throw(ArgumentError("nested function requires its own wrapper"))
        return x
    end
    Expr(x.head, (filter_body(a, enabled; statement=x.head === :block,caller) for a in x.args)...)
end

function instrument_definition(events, definition, caller=@__MODULE__)
    enabled = literal_events(events)
    definition isa Expr && definition.head === :function ||
        throw(ArgumentError("instrumentation supports long-form function definitions"))
    Expr(:function, definition.args[1], filter_body(definition.args[2], enabled; statement=true,caller))
end

macro instrument(events, definition)
    esc(instrument_definition(events, definition, __module__))
end

macro telemetry(args...)
    error("qualified telemetry marker requires an enclosing @instrument")
end
