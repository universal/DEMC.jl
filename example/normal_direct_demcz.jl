using Distributions
using DEMC
using LinearAlgebra
using Statistics

# set up target distribution: Multivariate Normal
ndim = 11 # Number of dimensions
μ = rand(ndim) # mean of each dimension
A = rand(Float64, (ndim, ndim))
Σ = A'*A + diagm(0 => 3 * ones(ndim)) # variance covariance matrix
Σ = Σ./maximum(Σ)
distr = MvNormal(μ, Σ)
# log objective function
log_obj(mean) = log(pdf(MvNormal(μ, Σ), mean))

# set up of DEMCz chain
Npar = length(μ)
blockindex = [1:Npar] # parameter blocks: here choose all parameters to be updated simultaenously
Nblocks = length(blockindex)
eps_scale = 1e-5*ones(Npar) # scale of random error around DE update
γ = 2.38 # scale of DE update, 2.38 is the "optimal" number for a normal distribution
N = 30
K = 10
Z = rand(Float64, (10*ndim, ndim))

# Number of iterations in Chain
Nburn = 10000
Ngeneration  = 10000

mc_burn = DEMC.demcz_sample(log_obj, Z, N, K, Nburn, Nblocks, blockindex, eps_scale, γ)
chainflat = DEMC.flatten_chain(mc_burn.chain, N, Nburn, Npar)'
Z = chainflat[end-100*ndim+1:end, :] # new initial Z
# run final chain
mc = DEMC.demcz_sample(log_obj, Z, N, K, Ngeneration, Nblocks, blockindex, eps_scale, γ)

# did we converge?
accept_ratio, Rhat = convergence_check(mc.chain, mc.log_obj, N, Ngeneration, Npar, "./img/demcz_normal/" ; verbose = true)

# estimates
chainflat = DEMC.flatten_chain(mc.chain, N, Ngeneration, Npar)'
# bhat = mean(chainflat,1)[:]
# println("\n estimates: ", bhat, "\n dist to true: ", bhat - μ)
# bhat = median(chainflat,1)[:]
# println("\n estimates: ", bhat, "\n dist to true: ", bhat - μ)

# covariance of estimates
b, Σb = mean_cov_chain(mc.chain, N, Ngeneration, Npar)


# plot simulated vs true distribution
using Plots
gr()
using Distributions


se = sqrt.(diag(Σ))
x1 = range(μ[1]-4*se[1], stop = μ[1] + 4*se[1], length = 200)
normal1 = pdf.(Normal(μ[1], se[1]),x1)
x2 =  range(μ[2]-4*se[2], stop = μ[2] + 4*se[2], length = 200)
normal2 = pdf.(Normal(μ[2], se[2]),x2)


h1 = histogram(chainflat[:,1], lab = "DEMCz, N = $N, T = $Ngeneration", normed=true, nbin = 33)
plot!(x1, normal1, lab="target", linewidth = 3)
h2 = histogram(chainflat[:,2], lab = "DEMCz, N = $N, T = $Ngeneration", normed=true, nbin = 33)
plot!(x2, normal2, lab="target", linewidth = 3)

p = plot(h1, h2, layout=(2,1) )
savefig(p,"./img/normal_direct_demcz_hist_1_2.png")
