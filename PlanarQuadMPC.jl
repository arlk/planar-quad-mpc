"""

 █████╗  ██████╗██████╗ ██╗
██╔══██╗██╔════╝██╔══██╗██║
███████║██║     ██████╔╝██║
██╔══██║██║     ██╔══██╗██║
██║  ██║╚██████╗██║  ██║███████╗
╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

File:       PlanarQuadMPC.jl
Author:     Gabriel Barsi Haberfeld, 2020. gbh2@illinois.edu
Function:   This program implemetns an MPC controller for trajectory tracking of
            a planar quadrotor.

Instructions:   Run this file in juno with Julia 1.5.1 or later.
Requirements:   JuMP, Ipopt, Plots, LinearAlgebra, BenchmarkTools.

"""

using JuMP, Ipopt
using Plots, LinearAlgebra
using BenchmarkTools
using Random
using RecipesBase
using SparseArrays
using Statistics
using Printf
using LaTeXStrings
using Measures
import Distributions: MvNormal
import Random.seed!
g = 9.81

function dynamics(x = 0.0 .* zeros(6), u = 0.0 .* zeros(2), dt = 1.0)
    #x = [px pz θ vx vz θ̇]
    #     1  2  3 4  5  6
    px = x[1]
    pz = x[2]
    θ = x[3]
    vx = x[4]
    vz = x[5]
    θ̇ = x[6]
    x0 = copy(x)
    x[1] = vx * cos(θ) - vz * sin(θ)
    x[2] = vx * sin(θ) + vz * cos(θ)
    x[3] = θ̇
    x[4] = vz * θ̇ - g * sin(θ)
    x[5] = -vx * θ̇ - g * cos.(θ) + u[1]
    x[6] = 0.0 + u[2]
    x = x * dt + x0
end

function test_dynamics()
    dt = 0.1
    t = Array(0:0.1:1)
    N = length(t)
    x = 0.0 .* zeros(6)
    x[3] = -0.1
    u = 0.0 .* zeros(2)
    xv = 0.0 .* zeros(6, N)
    for i = 1:N
        u[1] = 10.0
        u[2] = 0.0 * (cos(t[i] / 10.0) - 0.5)
        x = dynamics(x, u, dt)
        @show u, x
    end
end

function SimpleMPC(
    x0,
    xref = 0.0 .* zeros(6),
    θlim = Inf,
    θ̇lim = Inf,
    vxlim = Inf,
    vzlim = Inf,
    dt = 0.1,
    N = 10,
)
    MPC = Model(optimizer_with_attributes(
        Ipopt.Optimizer,
        "max_iter" => 5000,
        "print_level" => 0,
    ))
    @variable(MPC, px[i = 0:N])
    @variable(MPC, pz[i = 0:N])
    @variable(MPC, -θlim <= θ[i = 0:N] <= θlim)
    @variable(MPC, -vxlim <= vx[i = 0:N] <= vxlim)
    @variable(MPC, -vzlim <= vz[i = 0:N] <= vxlim)
    @variable(MPC, -θ̇lim <= θ̇[i = 0:N] <= θ̇lim)
    @variable(MPC, 0 <= uF[i = 0:N-1])
    @variable(MPC, uM[i = 0:N-1])

    @constraint(MPC, px[0] == x0[1])
    @constraint(MPC, pz[0] == x0[2])
    @constraint(MPC, θ[0] == x0[3])
    @constraint(MPC, vx[0] == x0[4])
    @constraint(MPC, vz[0] == x0[5])
    @constraint(MPC, θ̇[0] == x0[6])

    #x = [px pz θ vx vz θ̇]
    #     1  2  3 4  5  6
    for k = 0:N-1
        @NLconstraint(MPC, px[k+1] == px[k] + (vx[k] * cos(θ[k]) - vz[k] * sin(θ[k])) * dt)
        @NLconstraint(MPC, pz[k+1] == pz[k] + (vx[k] * sin(θ[k]) + vz[k] * cos(θ[k])) * dt)
        @constraint(MPC, θ[k+1] == θ[k] + θ̇[k] * dt)
        @NLconstraint(MPC, vx[k+1] == vx[k] + (vz[k] * θ̇[k] - g * sin(θ[k])) * dt)
        @NLconstraint(MPC, vz[k+1] == vz[k] + (-vx[k] * θ̇[k] - g * cos(θ[k]) + uF[k]) * dt)
        @constraint(MPC, θ̇[k+1] == θ̇[k] + uM[k] * dt)
    end

    @NLobjective(MPC, Min, sum(px[i] + pz[i] for i = 1:N))
    optimize!(MPC)
    return value.(uF), value.(uM), value.(px), value.(pz)
end

function runSimpleMPC()
    x = [1.0 1.0 0.0 0.0 0.0 0.0]
    dt = 0.01
    for t = 1:30
        uF, uM, px, pz = SimpleMPC(x, zeros(6), pi / 4, pi / 3, 2, 1, dt)
        u = [uF[0] uM[0]]
        x = dynamics(x, u, dt)
        @show u, x
    end
end
