
type VarMpFormIndexStatus{V<:Variable}
    variable::V
    status_in_basic_sol::Int
end

type ConstrMpFormIndexStatus{C<:Constraint}
    constraint::C
    status_in_basic_sol::Int
end

type LpBasisRecord
    name::String
    vars_in_basis::Vector{VarMpFormIndexStatus}
    constr_in_basis::Vector{ConstrMpFormIndexStatus}
end

LpBasisRecord(name::String) = LpBasisRecord(name, Vector{VarMpFormIndexStatus}(),
                              Vector{ConstrMpFormIndexStatus}())

LpBasisRecord() = LpBasisRecord("basis")

function clear(basis::LpBasisRecord; remove_marks_in_vars=true,
               remove_marks_in_constrs=true)::Void

    if remove_marks_in_vars
        for var in basis.vars_in_basis
            var.is_info_updated = false
        end
        empty!(basis.vars_in_basis)
    end

    if remove_marks_in_constrs
        for constr in constr_in_basis
            constr.is_info_updated = false
        end
        empty!(basis.constrsinbasis)
    end
    return
end

# needed for partial solution
type VariableSolInfo{V<:Variable}
    variable::V
    value::Float
end

function apply_var_info(var_sol_info::VariableSolInfo)::Void
    variable = var_sol_info.variable
    value = var_sol_info.value
    problem = variable.problem
    update_partial_solution(problem,variable,value)
end

# TODO: impl properly the var/constr manager
abstract type AbstractVarIndexManager end
abstract type AbstractConstrIndexManager end

type SimpleVarIndexManager <: AbstractVarIndexManager
    active_static_list::Vector{Variable}
    active_dynamic_list::Vector{Variable}
    unsuitable_static_list::Vector{Variable}
    unsuitable_dynamic_list::Vector{Variable}
end

SimpleVarIndexManager() = SimpleVarIndexManager(Vector{Variable}(),
        Vector{Variable}(), Vector{Variable}(), Vector{Variable}())

function add_in_var_manager(var_manager::SimpleVarIndexManager, var::Variable)
    if var.status == Active && var.flag == 's'
        list = var_manager.active_static_list
    elseif var.status == Active && var.flag == 'd'
        list = var_manager.active_dynamic_list
    elseif var.status == Unsuitable && var.flag == 's'
        list = var_manager.unsuitable_static_list
    elseif var.status == Unsuitable && var.flag == 'd'
        list = var_manager.unsuitable_dynamic_list
    else
        error("Status $(var.status) and flag $(var.flag) are not supported")
    end
    push!(list, var)
end

type SimpleConstrIndexManager <: AbstractConstrIndexManager
    active_static_list::Vector{Constraint}
    active_dynamic_list::Vector{Constraint}
    unsuitable_static_list::Vector{Constraint}
    unsuitable_dynamic_list::Vector{Constraint}
end

SimpleConstrIndexManager() = SimpleConstrIndexManager(Vector{Constraint}(),
        Vector{Constraint}(), Vector{Constraint}(), Vector{Constraint}())

function add_in_constr_manager(constr_manager::SimpleConstrIndexManager,
                            constr::Constraint)

    if constr.status == Active && constr.flag == 's'
        list = constr_manager.active_static_list
    elseif constr.status == Active && constr.flag == 'd'
        list = constr_manager.active_dynamic_list
    elseif constr.status == Unsuitable && constr.flag == 's'
        list = constr_manager.unsuitable_static_list
    elseif constr.status == Unsuitable && constr.flag == 'd'
        list = constr_manager.unsuitable_dynamic_list
    else
        error("Status $(constr.status) and flag $(constr.flag) are not supported")
    end
    push!(list, constr)
end

function remove_from_constr_manager(constr_manager::SimpleConstrIndexManager,
        constr::Constraint)
    if constr.status == Active && constr.flag == 's'
        list = constr_manager.active_static_list
    elseif constr.status == Active && constr.flag == 'd'
        list = constr_manager.active_dynamic_list
    elseif constr.status == Unsuitable && constr.flag == 's'
        list = constr_manager.unsuitable_static_list
    elseif constr.status == Unsuitable && constr.flag == 'd'
        list = constr_manager.unsuitable_dynamic_list
    else
        error("Status $(constr.status) and flag $(constr.flag) are not supported")
    end
    idx = findfirst(list, constr)
    deleteat!(list, idx)
end

struct ProblemCounter
    value::Int
end

abstract type Problem end

type CompactProblem{VM <: AbstractVarIndexManager,
                    CM <: AbstractConstrIndexManager} <: Problem

    # probInfeasiblesFlag::Bool

    # objvalueordermagnitude::Float
    prob_is_built::Bool

    optimizer::Nullable{MOI.AbstractOptimizer}
    # primalFormulation::LPform

    var_manager::VM
    constr_manager::CM

    ### Current solutions
    obj_val::Float
    obj_bound::Float
    in_primal_lp_sol::Set{Variable}
    non_zero_red_cost_vars::Set{Variable}
    in_dual_sol::Set{Constraint}

    partial_solution_value::Float
    partial_solution::Dict{Variable,Float}

    # Recorded solutions, may be integer or not
    primal_sols::Vector{PrimalSolution}
    dual_sols::Vector{DualSolution}

    # needed for new preprocessing
    preprocessed_constrs_list::Vector{Constraint}
    preprocessed_vars_list::Vector{Variable}

    counter::VarConstrCounter
    var_constr_vec::Vector{VarConstr}

    # added for more efficiency and to fix bug
    # after columns are cleaned we can t ask for red costs
    # before the MIPSolver solves the master again.
    # It is put to true in retrieveRedCosts()
    # It is put to false in resetSolution()
    is_retrieved_red_costs::Bool
end

function CompactProblem{VM,CM}(counter::VarConstrCounter) where {
    VM <: AbstractVarIndexManager,
    CM <: AbstractConstrIndexManager}

    optimizer = Nullable{MOI.AbstractOptimizer}()

    primal_vec = Vector{PrimalSolution}([PrimalSolution()])
    dual_vec = Vector{DualSolution}([DualSolution()])

    CompactProblem(false, optimizer, VM(), CM(), Inf, -Inf, Set{Variable}(),
                   Set{Variable}(), Set{Constraint}(), 0.0, Dict{Variable,Float}(),
                   primal_vec, dual_vec, Vector{Constraint}(), Vector{Variable}(),
                   counter, Vector{VarConstr}(), false)
end

const SimpleCompactProblem = CompactProblem{SimpleVarIndexManager,SimpleConstrIndexManager}


# function initialize_problem_optimizer(extended_problem::ExtendedProblem, problemidx_optimizer_map::Dict{Int,MOI.AbstractOptimizer})
    ## Goes through each problem in extended_problem, check its index and call function
    ## initialize_problem_optimizer(index, optimizer), using the dictionary
# end

function initialize_problem_optimizer(problem::CompactProblem,
                                      optimizer::MOI.AbstractOptimizer)
    optimizer = MOIU.MOIU.CachingOptimizer(ModelForCachingOptimizer{Float64}(),
                                           optimizer)
    f = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm{Float}[], 0.0)
    MOI.set!(optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float}}(),f)
    MOI.set!(optimizer, MOI.ObjectiveSense(), MOI.MinSense)
    problem.optimizer = Nullable{MOI.AbstractOptimizer}(optimizer)
end


type ExtendedProblem <: Problem
    master_problem::CompactProblem # restricted master in DW case.
    pricing_vect::Vector{Problem}
    separation_vect::Vector{Problem}
    params::Params
    counter::VarConstrCounter
    solution::PrimalSolution
    primal_inc_bound::Float
    dual_inc_bound::Float
    subtree_size_by_depth::Int
end

function ExtendedProblemConstructor(master_problem::CompactProblem{VM, CM},
        pricing_vect::Vector{Problem}, separation::Vector{Problem},
        counter::VarConstrCounter, params::Params, primal_inc_bound::Float,
        dual_inc_bound::Float) where {VM <: AbstractVarIndexManager,
        CM <: AbstractConstrIndexManager}
    return ExtendedProblem(master_problem, pricing_vect, separation, params,
        counter, PrimalSolution(), primal_inc_bound, dual_inc_bound, 0)
end

function retreive_primal_sol(problem::Problem) ## Store it in problem.primal_sols
    problem.obj_val = MOI.get(get(problem.optimizer), MOI.ObjectiveValue())
    println("Objective value: ", problem.obj_val)
    const var_list = problem.var_manager.active_static_list
    new_sol = Dict{Variable, Float}()
    new_obj_val = MOI.get(get(problem.optimizer), MOI.ObjectiveValue())
    for var_idx in 1:length(var_list)
        var_list[var_idx].val = MOI.get(get(problem.optimizer),
            MOI.VariablePrimal(), var_list[var_idx].moi_index)
        println("Var ", var_list[var_idx].name, " = ", var_list[var_idx].val)
        if var_list[var_idx].val > 0.0
            push!(problem.in_primal_lp_sol, var_list[var_idx])
            new_sol[var_list[var_idx]] = var_list[var_idx].val
        end
    end
    push!(problem.primal_sols, PrimalSolution(new_obj_val, new_sol))
end

function retreive_dual_sol(problem::Problem)
    problem.obj_bound = MOI.get(get(problem.optimizer), MOI.ObjectiveBound())
    # if MOI.canget(get(problem.optimizer), MOI.ConstraintDual())
    # end
    push!(problem.dual_sols, DualSolution(problem.obj_bound,
        Dict{Constraint, Float}()))
end

function retreive_solution(problem::Problem)
    retreive_primal_sol(problem)
    retreive_dual_sol(problem)
end

function sol_is_integer(sol::Dict{Variable, Float}, tolerance::Float)
    for var_val in sol
        if (!primal_value_is_integer(var_val.second, tolerance)
                && (var_val.first.vc_type == 'I' || var_val.first.vc_type == 'B'))
            println("Sol is fractional.")
            return false
        end
    end
    println("Solution is integer!")
    return true
end


### addvariable changes problem and MOI cachingOptimizer.model_cache
### and sets the index of the variable
function add_variable(problem::Problem, var::Variable)
    add_in_var_manager(problem.var_manager, var)
    var.moi_index = MOI.addvariable!(get(problem.optimizer))
    MOI.modify!(get(problem.optimizer),
                MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
                MOI.ScalarCoefficientChange{Float}(var.moi_index, var.cost_rhs))
    MOI.addconstraint!(get(problem.optimizer), MOI.SingleVariable(var.moi_index),
                       MOI.Interval(var.lower_bound, var.upper_bound))
end

### addconstraint changes problem and MOI cachingOptimizer.model_cache
### and sets the index of the constraint
function add_constraint(problem::Problem, constr::Constraint)
    add_in_constr_manager(problem.constr_manager, constr)
    f = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm{Float}[], 0.0)
    constr.moi_index = MOI.addconstraint!(get(problem.optimizer), f,
            constr.set_type(constr.cost_rhs))
end

function add_full_constraint(problem::Problem, constr::BranchConstr)
    add_in_constr_manager(problem.constr_manager, constr)
    terms = MOI.ScalarAffineTerm{Float}[]
    for var_val in constr.member_coef_map
        push!(terms, MOI.ScalarAffineTerm{Float}(var_val.second, var_val.first.moi_index))
    end
    f = MOI.ScalarAffineFunction(terms, 0.0)
    constr.moi_index = MOI.addconstraint!(get(problem.optimizer), f,
            constr.set_type(constr.cost_rhs))
end

function delete_constraint(problem::Problem, constr::BranchConstr)
    ### When deleting a constraint, its MOI index becomes invalid
    remove_from_constr_manager(problem.constr_manager, constr)
    MOI.delete!(get(problem.optimizer), constr.moi_index)
    constr.moi_index = MOI.ConstraintIndex{MOI.ScalarAffineFunction, constr.set_type}(-1)
end

function add_membership(var::Variable, constr::Constraint,
        problem::Problem, coef::Float)
    var.member_coef_map[constr] = coef
    constr.member_coef_map[var] = coef
    MOI.modify!(get(problem.optimizer), constr.moi_index,
                MOI.ScalarCoefficientChange{Float}(var.moi_index, coef))
end

function add_membership(var::SubprobVar, constr::MasterConstr,
        problem::Problem, coef::Float)
    var.master_constr_coef_map[constr] = coef
    constr.subprob_var_coef_map[var] = coef
end

function add_membership(var::MasterVar, constr::MasterConstr,
        problem::Problem, coef::Float)
    var.member_coef_map[constr] = coef
    constr.member_coef_map[var] = coef
    MOI.modify!(get(problem.optimizer), constr.moi_index,
                MOI.ScalarCoefficientChange{Float}(var.moi_index, coef))
end

function optimize(problem::Problem)

    MOI.optimize!(get(problem.optimizer))
    status = MOI.get(get(problem.optimizer), MOI.TerminationStatus())
    println("Optimization finished with status: ", status)

    if MOI.get(get(problem.optimizer), MOI.ResultCount()) >= 1
        retreive_solution(problem)
    else
        println("Solver has no result to show.")
    end

    return status
end