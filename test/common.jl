using DiffEqProblemLibrary, DiffEqBase

prob = prob_ode_linear
dt=1/2^(4)

sol =solve(prob,feuler();dt=dt)
#plot(sol,plot_analytic=true)

sol =solve(prob,rk23(),dt=dt)

sol =solve(prob,rk45(),dt=dt)

sol =solve(prob,feh78(),dt=dt)

sol =solve(prob,ModifiedRosenbrock(),dt=dt)

sol =solve(prob,midpoint(),dt=dt)

sol =solve(prob,heun(),dt=dt)

sol =solve(prob,rk4(),dt=dt)

sol =solve(prob,feh45(),dt=dt)

prob = prob_ode_2Dlinear

sol =solve(prob,feuler(),dt=dt)

sol =solve(prob,rk23(),dt=dt)

sol =solve(prob,rk45(),dt=dt)

sol =solve(prob,feh78(),dt=dt)

#sol =solve(prob,ModifiedRosenbrock(),dt=dt) #ODE.jl issues with 2D

sol =solve(prob,midpoint(),dt=dt)

sol =solve(prob,heun(),dt=dt)

sol =solve(prob,rk4(),dt=dt)

sol =solve(prob,feh45(),dt=dt)

#=
prob = prob_ode_bigfloat2Dlinear

sol =solve(prob,feuler(),dt=dt)
TEST_PLOT && plot(sol,plot_analytic=true)

sol =solve(prob,rk23(),dt=dt)

sol =solve(prob,rk4()5,dt=dt)

sol =solve(prob,feh78(),dt=dt)

#sol =solve(prob,dt=0,alg=:ode23s) #ODE.jl issues

sol =solve(prob,midpoint(),dt=dt)

sol =solve(prob,heun(),dt=dt)

sol =solve(prob,rk4(),dt=dt)

sol =solve(prob,feh45(),dt=dt)
=#
