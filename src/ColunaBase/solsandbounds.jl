# alias only used in this file
const Primal = AbstractPrimalSpace
const Dual = AbstractDualSpace
const MinSense = AbstractMinSense
const MaxSense = AbstractMaxSense

# Bounds
struct Bound{Space<:AbstractSpace,Sense<:AbstractSense} <: Real
    value::Float64
    Bound{Space,Sense}(x::Number) where {Space,Sense} = new(x === NaN ? _defaultboundvalue(Space, Sense) : x)
end

_defaultboundvalue(::Type{<:Primal}, ::Type{<:MinSense}) = Inf
_defaultboundvalue(::Type{<:Primal}, ::Type{<:MaxSense}) = -Inf
_defaultboundvalue(::Type{<:Dual}, ::Type{<:MinSense}) = -Inf
_defaultboundvalue(::Type{<:Dual}, ::Type{<:MaxSense}) = Inf

"""
    Bound{Space,Sense}()

Create a default bound for a problem with objective sense `Sense<:AbstractSense` in `Space<:AbstractSpace`.  
"""
function Bound{Space,Sense}() where {Space<:AbstractSpace,Sense<:AbstractSense}
    val = _defaultboundvalue(Space, Sense)
    return Bound{Space,Sense}(val)
end

getvalue(b::Bound) = b.value
Base.float(b::Bound) = b.value

"""
    isbetter(b1, b2)

Returns true if bound b1 is better than bound b2.
The function take into account the space (primal or dual) and the objective sense (min, max) of the bounds.
"""
isbetter(b1::Bound{Sp,Se}, b2::Bound{Sp,Se}) where {Sp<:Primal,Se<:MinSense} = b1.value < b2.value
isbetter(b1::Bound{Sp,Se}, b2::Bound{Sp,Se}) where {Sp<:Primal,Se<:MaxSense} = b1.value > b2.value
isbetter(b1::Bound{Sp,Se}, b2::Bound{Sp,Se}) where {Sp<:Dual,Se<:MinSense} = b1.value > b2.value
isbetter(b1::Bound{Sp,Se}, b2::Bound{Sp,Se}) where {Sp<:Dual,Se<:MaxSense} = b1.value < b2.value

"""
    diff(b1, b2)

Distance between a primal bound and a dual bound that have the same objective sense.
Distance is non-positive if dual bound reached primal bound.
"""
function Base.diff(pb::Bound{<:Primal,<:MinSense}, db::Bound{<:Dual,<:MinSense})
    return pb.value - db.value
end

function Base.diff(db::Bound{<:Dual,<:MinSense}, pb::Bound{<:Primal,<:MinSense})
    return pb.value - db.value
end

function Base.diff(pb::Bound{<:Primal,<:MaxSense}, db::Bound{<:Dual,<:MaxSense})
    return db.value - pb.value
end

function Base.diff(db::Bound{<:Dual,<:MaxSense}, pb::Bound{<:Primal,<:MaxSense})
    return db.value - pb.value
end

"""
    gap

relative gap. Gap is non-positive if pb reached db
"""
function gap(pb::Bound{<:Primal,<:MinSense}, db::Bound{<:Dual,<:MinSense})
    return diff(pb, db) / abs(db.value)
end

function gap(db::Bound{<:Dual,<:MinSense}, pb::Bound{<:Primal,<:MinSense})
    return diff(pb, db) / abs(db.value)
end

function gap(pb::Bound{<:Primal,<:MaxSense}, db::Bound{<:Dual,<:MaxSense})
    return diff(pb, db) / abs(pb.value)
end

function gap(db::Bound{<:Dual,<:MaxSense}, pb::Bound{<:Primal,<:MaxSense})
    return diff(pb, db) / abs(pb.value)
end

"""
    printbounds(db, pb [, io])
    
Prints the lower and upper bound according to the objective sense.

Can receive io::IO as an input, to eventually output the print to a file or buffer.
"""
function printbounds(db::Bound{<:Dual,S}, pb::Bound{<:Primal,S}, io::IO=Base.stdout) where {S<:MinSense}
    Printf.@printf io "[ %.4f , %.4f ]" getvalue(db) getvalue(pb)
end

function printbounds(db::Bound{<:Dual,S}, pb::Bound{<:Primal,S}, io::IO=Base.stdout) where {S<:MaxSense}
    Printf.@printf io "[ %.4f , %.4f ]" getvalue(pb) getvalue(db)
end

function Base.show(io::IO, b::Bound)
    print(io, getvalue(b))
end

Base.promote_rule(B::Type{<:Bound}, ::Type{<:AbstractFloat}) = B
Base.promote_rule(B::Type{<:Bound}, ::Type{<:Integer}) = B
Base.promote_rule(B::Type{<:Bound}, ::Type{<:AbstractIrrational}) = B
Base.promote_rule(::Type{<:Bound{<:Primal,Se}}, ::Type{<:Bound{<:Dual,Se}}) where {Se<:AbstractSense} = Float64

Base.convert(::Type{<:AbstractFloat}, b::Bound) = b.value
Base.convert(::Type{<:Integer}, b::Bound) = b.value
Base.convert(::Type{<:AbstractIrrational}, b::Bound) = b.value
Base.convert(B::Type{<:Bound}, f::AbstractFloat) = B(f)
Base.convert(B::Type{<:Bound}, i::Integer) = B(i)
Base.convert(B::Type{<:Bound}, i::AbstractIrrational) = B(i)

Base.:-(b::B) where {B<:Bound} = B(-b.value)
Base.:+(b1::B, b2::B) where {B<:Bound} = B(b1.value + b2.value)
Base.:-(b1::B, b2::B) where {B<:Bound} = B(b1.value - b2.value)
Base.:*(b1::B, b2::B) where {B<:Bound} = B(b1.value * b2.value)
Base.:/(b1::B, b2::B) where {B<:Bound} = B(b1.value / b2.value)
Base.:(==)(b1::B, b2::B) where {B<:Bound} = b1.value == b2.value
Base.:<(b1::B, b2::B) where {B<:Bound} = b1.value < b2.value
Base.:(<=)(b1::B, b2::B) where {B<:Bound} = b1.value <= b2.value
Base.:(>=)(b1::B, b2::B) where {B<:Bound} = b1.value >= b2.value
Base.:>(b1::B, b2::B) where {B<:Bound} = b1.value > b2.value

"""
    TerminationStatus

Theses statuses are the possible reasons why an algorithm stopped the optimization. 
When a subsolver is called through MOI, the
MOI [`TerminationStatusCode`](https://jump.dev/MathOptInterface.jl/stable/apireference/#MathOptInterface.TerminationStatusCode)
is translated into a Coluna `TerminationStatus`.

Description of the termination statuses: 
- `OPTIMAL` : the algorithm found a global optimal solution given the optimality tolerance.
- `INFEASIBLE` : the algorithm proved infeasibility
- `TIME_LIMIT` : the algorithm stopped because of the time limit
- `NODE_LIMIT` : the branch-and-bound based algorithm stopped due to the node limit
- `OTHER_LIMIT` : the algorithm stopped because of a limit that is neither the time limit 
nor the node limit

If the algorithm has not been called, the default value of the termination status should be:
- `UNKNOWN_TERMINATION_STATUS`

If the subsolver called through MOI returns a 
`TerminationStatusCode` that is not `MOI.OPTIMAL`, `MOI.INFEASIBLE`, `MOI.TIME_LIMIT`, `MOI.NODE_LIMIT`, or 
`MOI.OTHER_LIMIT`:
- `UNCOVERED_TERMINATION_STATUS` : should not be used by a Coluna algorithm
"""
@enum(
    TerminationStatus, OPTIMAL, INFEASIBLE, TIME_LIMIT, NODE_LIMIT, OTHER_LIMIT, 
    UNKNOWN_TERMINATION_STATUS, UNCOVERED_TERMINATION_STATUS
)

"""
    SolutionStatus

Description of the solution statuses:
- `FEASIBLE_SOL` : the solution is feasible
- `INFEASIBLE_SOL` : the solution is not feasible

If there is no solution or if we don't have information about the solution, the 
solution status should be :
- `UNKWNOW_SOLUTION_STATUS`

"""
@enum(
    SolutionStatus, FEASIBLE_SOL, INFEASIBLE_SOL, UNKNOWN_FEASIBILITY, 
    UNKNOWN_SOLUTION_STATUS, UNCOVERED_SOLUTION_STATUS
)

"""
    convert_status(status::MOI.TerminationStatusCode) -> Coluna.TerminationStatus
    convert_status(status::Coluna.TerminationStatus) -> MOI.TerminationStatusCode
    convert_status(status::MOI.ResultStatusCode) -> Coluna.SolutionStatus
    convert_status(status::Coluna.SolutionStatus) -> MOI.ResultStatusCode

Convert a termination or solution `status` of a given type to the corresponding status in another type.
This method is used to communicate between Coluna and MathOptInterface.
"""
function convert_status(moi_status::MOI.TerminationStatusCode)
    moi_status == MOI.OPTIMAL && return OPTIMAL
    moi_status == MOI.INFEASIBLE && return INFEASIBLE
    moi_status == MOI.TIME_LIMIT && return TIME_LIMIT
    moi_status == MOI.NODE_LIMIT && return NODE_LIMIT
    moi_status == MOI.OTHER_LIMIT && return OTHER_LIMIT
    return UNCOVERED_TERMINATION_STATUS
end

function convert_status(coluna_status::TerminationStatus)
    coluna_status == OPTIMAL && return MOI.OPTIMAL
    coluna_status == INFEASIBLE && return MOI.INFEASIBLE
    coluna_status == TIME_LIMIT && return MOI.TIME_LIMIT
    coluna_status == NODE_LIMIT && return MOI.NODE_LIMIT
    coluna_status == OTHER_LIMIT && return MOI.OTHER_LIMIT
    return MOI.OTHER_LIMIT
end

function convert_status(moi_status::MOI.ResultStatusCode)
    moi_status == MOI.NO_SOLUTION && return UNKNOWN_SOLUTION_STATUS
    moi_status == MOI.FEASIBLE_POINT && return FEASIBLE_SOL
    moi_status == MOI.INFEASIBLE_POINT && return INFEASIBLE_SOL
    return UNCOVERED_SOLUTION_STATUS
end

function convert_status(coluna_status::SolutionStatus)
    coluna_status == FEASIBLE_SOL && return MOI.FEASIBLE_POINT
    coluna_status == INFEASIBLE_SOL && return MOI.INFEASIBLE_POINT
    return MOI.OTHER_RESULT_STATUS
end

# Solution
struct Solution{Model<:AbstractModel,Decision,Value} <: AbstractDict{Decision,Value}
    model::Model
    bound::Float64
    status::SolutionStatus
    sol::DynamicSparseArrays.PackedMemoryArray{Decision,Value}
end

"""
    Solution(
        model::AbstractModel,
        decisions::Vector,
        values::Vector,
        solution_values::Float64,
        status::SolutionStatus
    )

Create a solution to the `model`. Other arguments are: 
- `decisions` is a vector with the index of each decision.
- `values` is a vector with the values for each decision.
- `solution_value` is the value of the solution.
- `status` is the solution status.
"""
function Solution{Mo,De,Va}(model::Mo, decisions::Vector{De}, values::Vector{Va}, solution_value::Float64, status::SolutionStatus) where {Mo<:AbstractModel,De,Va}
    sol = DynamicSparseArrays.dynamicsparsevec(decisions, values)
    return Solution(model, solution_value, status, sol)
end

"""
    getsol(solution)
    
Return the dynamic sparse vector that describes `solution`.
"""
getsol(s::Solution) = s.sol

"""
    getvalue(solution) -> Float64

Return the value of `solution`.
"""
getvalue(s::Solution) = float(s.bound)

"""
    getstatus(solution) -> SolutionStatus

Return the solution status of `solution`.
"""
getstatus(s::Solution) = s.status

Base.iterate(s::Solution) = iterate(s.sol)
Base.iterate(s::Solution, state) = iterate(s.sol, state)
Base.length(s::Solution) = length(s.sol)
Base.get(s::Solution{Mo,De,Va}, id::De, default) where {Mo,De,Va} = s.sol[id] # TODO : REMOVE
Base.getindex(s::Solution{Mo,De,Va}, id::De) where {Mo,De,Va} = Base.getindex(s.sol, id)
Base.setindex!(s::Solution{Mo,De,Va}, val::Va, id::De) where {Mo,De,Va} = s.sol[id] = val

function Base.filter(f::Function, s::S) where {S <: Solution}
    return S(s.model, s.bound, s.status, filter(f, s.sol))
end

function Base.show(io::IO, solution::Solution{Mo,De,Va}) where {Mo,De,Va}
    println(io, "Solution")
    for (decision, value) in solution
        println(io, "| ", decision, " = ", value)
    end
    Printf.@printf(io, "└ value = %.2f \n", getvalue(solution))
end
# Todo : revise method
Base.copy(s::S) where {S<:Solution} = S(s.bound, copy(s.sol))
