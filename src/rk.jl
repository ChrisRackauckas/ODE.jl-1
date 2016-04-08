# This file contains the implementation of explicit Runkge-Kutta
# solver from (Hairer & Wanner 1992 p.134, p.165-169).

include("tableaus.jl")

# intermediate level interface


immutable TableauStepper{StepType,MethodType} <: AbstractStepper
    tableau :: Tableau # Butcher tableau
end


function TableauStepper(tableau :: Tableau)
    if isadaptive(tableau)
        steptype = :adaptive
    else
        steptype = :fixed
    end

    if isexplicit(tableau)
        methodtype = :explicit
    else
        methodtype = :implicit
    end

    # convert the method table to T here
    return TableauStepper{steptype,methodtype}(tableau)
end


order(stepper :: TableauStepper) = minimum(order(stepper.tableau))


# TODO: possibly handle the initial stepsize and the tableau conversion here?
solve{T}(ode :: ExplicitODEInPlace, stepper :: TableauStepper{T,:explicit}, options :: Options) =
    Solution{TableauStepper{T,:explicit}}(ode,stepper,options)


# lower level interface

abstract AbstractTableauState


# explicit RK stepper

type RKTempArrays{T}
    y    :: T
    ynew :: T
    yerr :: T
    ks   :: Vector{T}
end


type TableauExplicitState{T,S} <: AbstractTableauState
    step :: Step{T,S}
    dt   :: T
    tmp  :: RKTempArrays{S}
    timeout :: Int
end

function show(io :: IO, state :: TableauExplicitState)
    show(state.step)
    println("dt      = $(state.dt)")
    println("timeout = $(state.timeout)")
    println("tmp     = $(state.tmp)")
end


function start{T}(s :: Solution{TableauStepper{T,:explicit}})
    t0, dt0, y0 = s.ode.t0, s.options.initstep, s.ode.y0

    # TODO: we should do the Butcher table conversion somewhere
    lk = lengthks(s.stepper.tableau)
    tmp = RKTempArrays(zero(y0), # y
                       zero(y0), # ynew
                       zero(y0), # yerr
                       Array(typeof(y0), lk)) # ks

    for i = 1:lk
        tmp.ks[i] = zero(y0)
    end

    # pre-initialize tmp.ks[1]
    s.ode.F!(t0,y0,tmp.ks[1])

    step = Step(t0,deepcopy(y0),deepcopy(tmp.ks[1]))

    timeout = 0 # for step control
    return TableauExplicitState(step,dt0,tmp,timeout)
end


function done{T,S}(s :: Solution{TableauStepper{T,S}}, state :: AbstractTableauState)
    return state.step.t >= s.options.tstop || state.dt < s.options.minstep
end


#####################
# Fixed step method #
#####################


function next(s :: Solution{TableauStepper{:fixed,:explicit}}, state :: TableauExplicitState)
    step = state.step
    tmp = state.tmp

    dof = length(step.y)
    b = s.stepper.tableau.b

    for k=1:lengthks(s.stepper.tableau)
        calc_next_k!(state.tmp, k, s.ode, s.stepper.tableau, step, state.dt)
        for d=1:dof
            step.y[d] += state.dt * b[k]*tmp.ks[k][d]
        end
    end
    step.t += state.dt
    return ((step.t,step.y), state)
end


########################
# Adaptive step method #
########################


function next(sol :: Solution{TableauStepper{:adaptive,:explicit}}, state :: TableauExplicitState)

    const timeout_const = 5

    # the initial values
    dt      = state.dt          # dt is the previous stepisze, it is
                                # modified inside the loop
    timeout = state.timeout

    tmp     = state.tmp
    step    = state.step

    # The while loop continues until we either find a stepsize which
    # leads to a small enough error or the stepsize reaches
    # prob.minstep

    while true

        # Do one step (assumes ks[1]==f0).  After calling tmp.ynew
        # holds the new step.
        # TODO: return ynew instead of passing it as tmp.ynew?
        err, newdt, timeout =
            rk_trial_step!(tmp, sol.ode, step, sol.stepper.tableau, dt, timeout, sol.options)

        if abs(newdt) < sol.options.minstep  # minimum step size reached, break
            println("Warning: dt < minstep.  Stopping.")
            # passing the newdt to state will result in done()
            state.dt = newdt
            break
        end

        if err > 1 # error is too large, repeat the step with smaller dt
            # redo step with smaller dt and reset the timeout
            dt      = newdt
            timeout = timeout_const
        else
            # step is accepted

            # preload ks[1] for the next step
            if isFSAL(sol.stepper.tableau)
                tmp.ks[1][:] = tmp.ks[end]
            else
                sol.ode.F!(step.t+dt, tmp.ynew, tmp.ks[1])
            end

            # Swap bindings of y and ytrial, avoids one copy
            step.y, tmp.ynew = tmp.ynew, step.y

            # Update state with the data from the step we have just
            # made:
            step.t += dt
            state.dt = newdt
            state.timeout = timeout
            break
        end
    end
    return ((step.t,step.y),state)
end


##########################
# Lower level algorithms #
##########################


function rk_trial_step!(tmp       :: RKTempArrays,
                        ode       :: ExplicitODEInPlace,
                        last_step :: Step,
                        tableau   :: TableauRKExplicit,
                        dt,
                        timeout,
                        options   :: Options)

    # tmp.y and tmp.yerr and tmp.ks are updated after this step
    rk_embedded_step!(tmp, ode, tableau, last_step, dt)

    # changes tmp.yerr (via in place update)
    err, newdt, timeout = stepsize_hw92!(tmp, last_step, tableau, dt, timeout, options)

    return err, newdt, timeout
end


function rk_embedded_step!(tmp       :: RKTempArrays,
                           ode       :: ExplicitODEInPlace,
                           tableau   :: Tableau,
                           last_step :: Step,
                           dt)
    # Does one embedded R-K step updating ytrial, yerr and ks.
    #
    # Assumes that ks[:,1] is already calculated!
    #
    # Modifies tmp.y, tmp.ynew and tmp.yerr only

    y      = last_step.y
    dof    = length(y)
    b      = tableau.b

    tmp.ynew[:] = 0
    tmp.yerr[:] = 0

    for s=1:lengthks(tableau)
        # we skip the first step beacause we assume that tmp.ks[1] is
        # already computed
        if s > 1
            calc_next_k!(tmp, s, ode, tableau, last_step, dt)
        end
        tmp.ynew[:] += b[1,s]*tmp.ks[s]
        tmp.yerr[:] += b[2,s]*tmp.ks[s]
    end

    tmp.yerr[:] = dt*(tmp.ynew-tmp.yerr)
    tmp.ynew[:] = y + dt*tmp.ynew

end


function stepsize_hw92!(tmp,
                        last_step :: Step,
                        tableau :: TableauRKExplicit,
                        dt,
                        timeout,
                        options :: Options)
    # Estimates the error and a new step size following Hairer &
    # Wanner 1992, p167 (with some modifications)
    #
    # If timeout>0 no step size increase is allowed, timeout is
    # decremented in here.
    #
    # Returns the error, newdt and the number of timeout-steps
    #
    # TODO:
    # - allow component-wise reltol and abstol?
    # - allow other norms

    ord = minimum(order(tableau))
    timout_after_nan = 5
    fac = [0.8, 0.9, 0.25^(1/(ord+1)), 0.38^(1/(ord+1))][1]
    facmax = 5.0 # maximal step size increase. 1.5-5
    facmin = 1./facmax  # maximal step size decrease. ?
    dof = length(last_step.y)

    # in-place calculate yerr./tol
    for d=1:dof

        # if outside of domain (usually NaN) then make step size smaller by maximum
        if isoutofdomain(tmp.y[d])
            return 10., dt*facmin, timout_after_nan
        end

        y0 = last_step.y[d] # TODO: is this supposed to be the last successful step?
        y1 = tmp.ynew[d]    # the approximation to the next step
        sci = (options.abstol + options.reltol*max(norm(y0),norm(y1)))
        tmp.yerr[d] = tmp.yerr[d]/sci # Eq 4.10
    end

    err = norm(tmp.yerr, 2) # Eq. 4.11
    newdt = min(options.maxstep, dt*max(facmin, fac*(1/err)^(1/(ord+1)))) # Eq 4.13 modified

    if timeout > 0
        newdt = min(newdt, dt)
        timeout -= 1
    end

    return err, newdt, timeout
end


# For clarity we pass the RKTempArrays part of the state separately,
# this is the only part of state that can be changed here
function calc_next_k!(tmp       :: RKTempArrays,
                      i         :: Int,
                      ode       :: ExplicitODEInPlace,
                      tableau   :: Tableau,
                      last_step :: Step,
                      dt)
    dof = length(last_step.y)
    t, a, c = last_step.t, tableau.a, tableau.c

    tmp.y[:] = last_step.y
    for j=1:i-1
        for d=1:dof
            tmp.y[d] += dt * tmp.ks[j][d] * a[i,j]
        end
    end
    ode.F!(t + c[i]*dt, tmp.y, tmp.ks[i])

    nothing
end