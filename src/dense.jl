# iterator for the dense output, can be wrapped around any other
# iterator supporting tspan by using the method keyword, for example
# ODE.newDenseProblem(..., method = ODE.bt_rk23, ...)

# type Step
#     t; y; dy
# end


type DenseState
    s0 :: Step; s1 :: Step
    last_tout
    first_step
    solver_state
    # used for storing the interpolation result
    ytmp
end


# TODO: would it be possible to make the DenseProblem a
# Solver{DenseProblem} instead?
immutable DenseProblem
    # TODO: solver has options in it, maybe we should move the points,
    # tspan, stopevent, roottol to options instead of having them
    # hanging around here?
    solver :: Solution
    points :: Symbol
    tspan
    stopevent :: Function
    roottol
end

# TODO: perhaps something like this?
# solve(ode, stepper :: DenseStepper, options :: Options) = Solver(ode,stepper,options)
# function solve(ode, stepper, options :: Options)
#     solver = Solver(ode, stepper, options)
#     Solver(ode,DenseStepper(solver),options)
# end


# normally we return the working array, which changes at each step and
# expect the user to copy it if necessary.  In order for collect to
# return the expected result we need to copy the output at each step.
collect{T}(t::Type{T}, prob::DenseProblem) = collect(t, imap(x->deepcopy(x),prob))


function dense(solver :: Solution;
               tspan = [Inf],
               points = :all,
               stopevent = (t,y)->false,
               roottol = 1e-5,
               kargs...)
    return DenseProblem(solver, points, tspan, stopevent, roottol)
end


function start(prob :: DenseProblem)
    t0  = prob.solver.ode.t0
    y0  = prob.solver.ode.y0
    dy0 = deepcopy(y0)
    prob.solver.ode.F!(t0,y0,dy0)
    step0 = Step(t0,deepcopy(y0),deepcopy(dy0))
    step1 = Step(t0,deepcopy(y0),deepcopy(dy0))
    solver_state = start(prob.solver)
    ytmp = deepcopy(y0)
    return DenseState(step0, step1, t0, true, solver_state, ytmp)
end


function next(prob :: DenseProblem, state :: DenseState)

    s0, s1 = state.s0, state.s1
    t0, t1 = s0.t, s1.t

    if state.first_step
        state.first_step = false
        return ((s0.t,s0.y),state)
    end

    # the next output time that we aim at
    t_goal = prob.tspan[findfirst(t->(t>state.last_tout), prob.tspan)]

    # the t0 == t1 part ensures that we make at least one step
    while t1 < t_goal

        # s1 is the starting point for the new step, while the new
        # step is saved in s0

        if done(prob.solver, state.solver_state)
            warn("The iterator was exhausted before the dense output completed.")
        else
            # at this point s0 holds the new step, "s2" if you will
            ((s0.t,s0.y[:]), state.solver_state) = next(prob.solver, state.solver_state)
        end

        # swap s0 and s1
        s0, s1 = s1, s0
        # update the state
        state.s0, state.s1 = s0, s1
        # and times
        t0, t1 = s0.t, s1.t

        # we made a successfull step and points == :all
        if prob.points == :all || prob.stopevent(t1,s1.y)
            t_goal = min(t_goal,t1)
            break
        end

    end

    # at this point we have t_goal∈[t0,t1] so we can apply the
    # interpolation

    prob.solver.ode.F!(t0,s0.y,s0.dy)
    prob.solver.ode.F!(t1,s1.y,s1.dy)

    if prob.stopevent(t1,s1.y)
        function stopfun(t)
            hermite_interp!(state.ytmp,t,s0,s1)
            res = typeof(t0)(prob.stopevent(t,state.ytmp))
            return 2*res-1      # -1 if false, +1 if true
        end
        t_goal = findroot(stopfun, [s0.t,s1.t], prob.roottol)
        # state.ytmp is already overwwriten to the correct result as a
        # side-effect of calling stopfun
    else
        hermite_interp!(state.ytmp,t_goal,s0,s1)
    end

    # update the last output time
    state.last_tout = t_goal

    return ((t_goal,state.ytmp),state)

end


function done(prob :: DenseProblem, state :: DenseState)

    return (
            done(prob.solver, state.solver_state) ||
            state.s1.t >= prob.tspan[end] ||
            prob.stopevent(state.s1.t,state.s1.y)
            )
end


function hermite_interp!(y,t,step0::Step,step1::Step)
    # For dense output see Hairer & Wanner p.190 using Hermite
    # interpolation. Updates y in-place.
    #
    # f_0 = f(x_0 , y_0) , f_1 = f(x_0 + h, y_1 )
    # this is O(3). TODO for higher order.

    y0,  y1  = step0.y, step1.y
    dy0, dy1 = step0.dy, step1.dy

    dt       = step1.t-step0.t
    theta    = (t-step0.t)/dt
    for i=1:length(y0)
        y[i] = ((1-theta)*y0[i] + theta*y1[i] + theta*(theta-1) *
                ((1-2*theta)*(y1[i]-y0[i]) + (theta-1)*dt*dy0[i] + theta*dt*dy1[i]) )
    end
    nothing
end


function findroot(f,rng,eps)
    xl, xr = rng
    fl, fr = f(xl), f(xr)

    if fl*fr > 0 || xl > xr
        error("Inconsistent bracket")
    end

    while xr-xl > eps
        xm = (xl+xr)/2
        fm = f(xm)

        if fm*fr > 0
            xr = xm
            fr = fm
        else
            xl = xm
            fl = fm
        end
    end

    return (xr+xl)/2
end