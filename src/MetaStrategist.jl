module MetaStrategist

using TestItems
using SHA
using TOML

export AbstractEvidenceStore
export Budget
export CandidateBinding
export CapabilityProfile
export CompiledExecutionPlan
export EvidenceReference
export InMemoryEvidenceStore
export ProblemDescriptor
export ResourceInventory
export ResourceSpec
export RunEvidence
export SolverCapability
export SolverCatalog
export STRATEGY_PLAN_SCHEMA
export StrategyComponent
export StrategyPlan
export UserGuidance

export append_evidence!
export compatible
export eligible_bindings
export execution_units
export query_evidence

include("capabilities.jl")
include("guidance.jl")
include("strategy_plan.jl")
include("specialization.jl")
include("preparation_receipts.jl")
include("strategy_archive.jl")
include("instrumentation.jl")
include("oracle.jl")
export @instrument, @telemetry, EventBuffer, observe!, events
export OracleProblem, OracleContract, OracleSession, evaluate!, oracle_result, AdapterContract, adapter_decision
export PhaseChoice, SuppressPhase, PhaseDefinition, PhaseCatalog, StrategyProfile, ExecutionIR
export register_phase!, resolve_strategy, strategy_snapshot, restore_strategy, prepare_strategy
export GenerationBudget, PreparedStrategy, execute!, clone_kernel
include("evidence.jl")
include("experiment_grammar.jl")

end
