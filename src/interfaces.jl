"""

We assume that the initial data y0 is given at tspan[1], and that
tspan[end] is the last integration time.

"""

function ode{T<:Number}(F, y0, tspan::AbstractVector{T}, stepper::AbstractStepper;
                jacobian::Function  = (t,y)->fdjacobian(F, t, y),
                # we need these options explicitly for the dtinit
                reltol::T   = eps(T)^T(1//3)/10,
                abstol::T   = eps(T)^T(1//2)/10,
                initstep::T = dtinit(F, y0, tspan, reltol, abstol; order=order(stepper))::T,
                kargs...)

    t0 = tspan[1]

    # construct a solver
    equation  = explicit_ineff(t0,y0,F,jac=jacobian)

    opts = Options{T}(;
                      tspan    = tspan,
                      reltol   = reltol,
                      abstol   = abstol,
                      initstep = initstep,
                      kargs...)
    solver = solve(equation,stepper,opts)

    # handle different directions of time integration
    if issorted(tspan)
        # do nothing, we are already set with the solver
        solution = collect(dense(solver))
    elseif issorted(reverse(tspan))
        # Reverse the time direction if necessary.  dense() only works
        # for positive time direction.

        # TODO: still ugly but slightly less bandaid-like then the
        # previous solution
        solution = map(ty->(2*t0-ty[1],ty[2]),collect(dense(reverse_time(solver))))
    else
        warn("Unsorted output times are not supported")
        return ([t0],[y0])
    end

    n = length(solution)

    # convert a list of pairs to a pair of arrays
    # TODO: leave it out as a list of pairs?
    tn = Array(T,n)
    yn = Array(typeof(y0),n)

    for (n,(t,y)) in enumerate(solution)
        tn[n] = t
        yn[n] = isa(y0,Number) ? y[1] : y
    end

    return (tn,yn)
end

ode23s(F,y0,t0;kargs...)        = ode_conv(F,y0,t0,ModifiedRosenbrockStepper; kargs...)
ode1(F,y0,t0;kargs...)          = ode_conv(F,y0,t0,RKStepperFixed{:bt_feuler}; kargs...)
ode2_midpoint(F,y0,t0;kargs...) = ode_conv(F,y0,t0,RKStepperFixed{:bt_midpoint}; kargs...)
ode2_heun(F,y0,t0;kargs...)     = ode_conv(F,y0,t0,RKStepperFixed{:bt_heun}; kargs...)
ode4(F,y0,t0;kargs...)          = ode_conv(F,y0,t0,RKStepperFixed{:bt_rk4}; kargs...)
ode21(F,y0,t0;kargs...)         = ode_conv(F,y0,t0,RKStepperAdaptive{:bt_rk21}; kargs...)
ode23(F,y0,t0;kargs...)         = ode_conv(F,y0,t0,RKStepperAdaptive{:bt_rk23}; kargs...)
ode45_fe(F,y0,t0;kargs...)      = ode_conv(F,y0,t0,RKStepperAdaptive{:bt_rk45}; kargs...)
ode45_dp(F,y0,t0;kargs...)      = ode_conv(F,y0,t0,RKStepperAdaptive{:bt_dopri5}; kargs...)
ode78(F,y0,t0;kargs...)         = ode_conv(F,y0,t0,RKStepperAdaptive{:bt_feh78}; kargs...)


function ode_conv{Ty,T}(F,y0::Ty,t0::AbstractVector{T},stepper;kargs...)

    if !isleaftype(T)
        error("The output times have to be of a concrete type.")
    elseif !(T <:AbstractFloat)
        error("The time variable should be a floating point number.")
    end

    if !isleaftype(Ty) & !isleaftype(eltype(Ty))
        error("The initial data has to be of a concrete type (or an array)")
    end

    ode(F,y0,t0,stepper{T}();kargs...)

end

const ode45 = ode45_dp


"""

A nasty hack to convert a solver with negative time direction into a
solver with positive time direction.  This is necessary as negative
time direction is not supported by steppers (including the dense
output).  This only works for ExplicitODE.

"""
function reverse_time(sol::Solver)
    ode, options, stepper = sol.ode, sol.options, sol.stepper

    t0 = ode.t0
    y0 = ode.y0

    # TODO: improve the implementation
    function F_reverse!(t,y,dy)
        ode.F!(2*t0-t,y,dy)
        dy[:]=-dy
    end

    # TODO: is that how the jacobian changes?
    function jac_reverse!(t,y,J)
        ode.jac!(2*t0-t,y,J)
        J[:]=-J
    end

    # ExplicitODE is immutable
    ode_reversed = ExplicitODE(t0,y0,F_reverse!,jac_reverse!)
    stopevent = options.stopevent

    # TODO: we are modifying options here, should we construct new
    # options insted?
    options.tstop     = 2*t0-options.tstop
    options.tspan     = reverse(2*t0.-options.tspan)
    options.stopevent = (t,y)->stopevent(2*t0-t,y)
    return solve(ode_reversed,stepper,options)
end
