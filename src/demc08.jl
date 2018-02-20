function demcz_sample(logobj, Zmat, N, K, Ngeneration, Nblocks, blockindex, eps_scale, γ)
    M, d = size(Zmat)
    X = Zmat[end-N+1:end, :]
    log_objcurrent = map(logobj, [X[i,:] for i = 1:N])
    mc = MC(Array{Float64}(N,  d, Ngeneration),Array{Float64}(N, Ngeneration), X, log_objcurrent)

    for ig = 1:Ngeneration
        for ic = 1:N
            Xcurrent, current_logobj = update_blocks(mc.Xcurrent[ic, :], mc.log_objcurrent[ic], Zmat, M, logobj, blockindex, eps_scale, γ, Nblocks)
            # update in chain
            mc.chain[ic, :, ig] = Xcurrent
            mc.log_obj[ic, ig] = current_logobj
            mc.Xcurrent[ic, :] = Xcurrent
            mc.log_objcurrent[ic] = current_logobj
        end
        if mod(ig, K) == 0.
            Zmat = vcat(Zmat, mc.Xcurrent)
            M += N
        end
    end
    return mc
end

function demcz_sample_par(logobj, Zmat, N, K, Ngeneration, Nblocks, blockindex, eps_scale, γ)
    wp = CachingPool(workers())
    Mval, d = size(Zmat)
    X = Zmat[end-N+1:end, :]
    log_objcurrent = pmap(wp, logobj, [X[i,:] for i = 1:N])
    mc = MC(Array{Float64}(N,  d, Ngeneration),Array{Float64}(N, Ngeneration), X, log_objcurrent)
    global Xcurrent = copy(mc.Xcurrent)
    global log_objcurrent = copy(mc.log_objcurrent)
    global Z = Zmat
    global M = Mval
    @everywhere global Z
    @everywhere global M
    @everywhere global Xcurrent
    @everywhere global log_objcurrent

    passobj(myid(), workers(), [:Xcurrent, :log_objcurrent], from_mod = DEMC, to_mod = DEMC)
    passobj(myid(), workers(), [:Z, :M], from_mod = DEMC, to_mod = DEMC)

    for ig = 1:Ngeneration
        passobj(myid(), workers(), [:Xcurrent, :log_objcurrent], from_mod = DEMC, to_mod = DEMC)
        res = pmap(wp, ic -> update_blocks(Xcurrent[ic,:], log_objcurrent[ic], Z, M, logobj, blockindex, eps_scale, γ, Nblocks), 1:N)
        for ic = 1:N
            # update in chain
            mc.chain[ic, :, ig] = res[ic][1]
            mc.log_obj[ic, ig] = res[ic][2]
            mc.Xcurrent[ic, :] = res[ic][1]
            mc.log_objcurrent[ic] = res[ic][2]
            Xcurrent[ic, :] = res[ic][1]
            log_objcurrent[ic] = res[ic][2]
        end

        if mod(ig, K) == 0.
            Z = vcat(Z, mc.Xcurrent)
            M += N
            passobj(myid(), workers(), [:Z, :M], from_mod = DEMC, to_mod = DEMC)
        end
    end
    return mc
end


function update_blocks(Xcurrent, current_logobj, Zmat, M, logobj, blockindex, eps_scale, γ, Nblocks)
    for ib in 1:Nblocks
        Xcurrent[:], current_logobj = update_demcz_chain_block(Xcurrent, current_logobj, ib, Zmat, M, logobj, blockindex, eps_scale, γ, Nblocks)
    end
    return Xcurrent, current_logobj
end


function update_demcz_chain_block(Xcurrent, current_logobj, ib, Zmat, M, logobj, blockindex, eps_scale, γ, Nblocks)
    Xproposal = copy(Xcurrent)
    # generate proposal
    set = collect(1:M)
    i1 = rand(set)
    deleteat!(set, i1)
    i2 = rand(set)
    de_diffvec = zeros(Xproposal)
    block = blockindex[ib]
    blocklen = length(block)
    if blocklen == 1
        de_diffvec[block] = γ*(Zmat[i1,block]- Zmat[i2,block]) + eps_scale[block] .* randn()
    else
        de_diffvec[block] = γ/sqrt(2*blocklen)*(Zmat[i1,block]-Zmat[i2,block]) + eps_scale[block] .* randn(blocklen)
    end
    Xproposal += de_diffvec
    log_objXprop = logobj(Xproposal)
    if log(rand()) < log_objXprop - current_logobj
        return Xproposal, log_objXprop
    else
        return Xcurrent, current_logobj
    end
end