# -------------- #
# B-Spline Basis #
# -------------- #

# constructor to accept spline params arguments, do some pre-processing
function Basis(::Spline, breaks::Vector, evennum::Int, k::Int)
    # error handling
    k < 0 && error("spline order must be positive")
    length(breaks) < 2 && error("Must have at least two breakpoints")
    any(diff(breaks) .< 0) && error("Breakpoints must be non-decreasing")

    if evennum == 0  # 43
        if length(breaks) == 2  # 44
            evennum = 2
        end
    else
        if length(breaks) == 2
            breaks = linspace(breaks[1], breaks[2], evennum)
        else
            error("Breakpoint squence must contain 2 values when evennum > 0")
        end
    end

    n = length(breaks) + k - 1
    a = breaks[1]
    b = breaks[end]
    Basis(Spline(), n, a, b, SplineParams(breaks, evennum, k))
end

# define methods for SplineParams type
Basis(p::SplineParams) = Basis(Spline(), p.breaks, p.evennum, p.k)

"""
Construct interpolation nodes, given SplineParams

Note that `p.k - 1` additional nodes will be inserted

##### Arguments

- `p::SplineParams`: `SplineParams` instance

##### Returns

- `x::Vector`: The Vector of 1d interpolation nodes.

"""
function nodes(p::SplineParams)
    breaks, evennum, k = p.breaks, p.evennum, p.k
    a = breaks[1]  # 20
    b = breaks[end]  # 21
    n = length(breaks) + k - 1  # 22
    x = cumsum(vcat(fill(a, k), breaks, fill(b, k)))  # 23
    x = (x[1+k:n+k] - x[1:n]) / k  # 24
    x[1] = a  # 25
    x[end] = b  # 26
    x
end

function derivative_op(p::SplineParams, order=1)
    breaks, evennum, k = p.breaks, p.evennum, p.k

    any(order .> k) && error("Order of differentiation can't be greater than k")

    # 38-40
    n = length(breaks) + k - 1
    kk = max(k - 1, k - order - 1)
    augbreaks = vcat(fill(breaks[1], kk), breaks, fill(breaks[end], kk))

    D = Array(SparseMatrixCSC{Float64,Int64}, abs(order), 1)

    if order > 0  # derivative
        temp = k ./ (augbreaks[k+1:n+k-1] - augbreaks[1:n-1])
        D[1] = spdiagm((-temp, temp), 0:1, n-1, n)

        for i=2:order
            temp = (k+1-i) ./ (augbreaks[k+1:n+k-i] - augbreaks[i:n-1])
            D[i] = spdiagm((-temp, temp), 0:1, n-i, n+1-i)*D[i-1]
        end
    else
        error("not implemented")
    end

    D, n-order, breaks[1], breaks[end], Any[breaks, evennum, k-order]
end

"""
Evaluate spline basis matrices for a certain order derivative at x

##### Arguments

- `p::SplineParams`: A `SplineParams` summarizing spline properties
- `x(nodes(p))` : the nodes at which to evaluate the basis matrices
- `order(0)` : The order(s) of derivative for which to evaluate the basis
matrices. `order=0` corresponds to the function itself, negative numbers
correspond to integrals.

##### Returns

- `B::SparseMatrixCSC` : Matrix containing the evaluation of basis functions
at each point in `x`. Each column represents a basis function.
- `x`: Points at which the functions were evaluated

"""
function evalbase(p::SplineParams, x=nodes(p), order=0)
    breaks, evennum, k = p.breaks, p.evennum, p.k

    # error handling
    k < 0 && error("spline order must be positive")
    !(issorted(breaks)) && error("Breakpoints must be non-decreasing")
    any(order .>= k) && error("Order of differentiation must be less than k")
    size(x, 2) > 1 && error("x must be a column vector")

    p = length(breaks)  # 53
    m = size(x, 1)  # 54
    minorder = minimum(order)  # 55

    # Augment the breakpoint sequence 57-59
    n = length(breaks)+k-1
    a = breaks[1]
    b = breaks[end]
    augbreaks = vcat(fill(a, k-minorder), breaks, fill(b, k-minorder))

    ind = lookup(augbreaks, x, 3)  # 69

    bas = zeros(m, k-minorder+1)  # 73
    bas[:, 1] = 1.0  # 74
    B = cell(length(order))  # 75

    # 76
    if maximum(order) > 0
        D = splidop(breaks, evennum, k, maximum(order))[1]
    end

    # 77
    if minorder < 0
        I = splidop(breaks, evennum, k, minorder)[1]
    end

    for j=1:k-minorder  # 78
        for jj=j:-1:1  # 79
            b0 = augbreaks[ind+jj-j]  # 80
            b1 = augbreaks[ind+jj]  # 81
            temp = bas[:, jj] ./ (b1 - b0)  # 82
            bas[:, jj+1] = (x - b0) .* temp + bas[:, jj+1]  # 83
            bas[:, jj] = (b1-x) .* temp  # 84
        end
        # bas now contains the order `j` spline basis
        ii = find((k-j) .== order)  # 87
        if !(isempty(ii))  # 88
            ii = ii[1]  # 89

            # Put values in appropriate columns of a sparse matrix
            r = collect(1:m)''  # 91
            r = r[:, fill(1, k-order[ii]+1)]  # 91
            c = collect((order[ii] - k:0) - (order[ii] - minorder))'  # 92
            c = c[fill(1, m), :] + ind[:, fill(1, k-order[ii] + 1)]  # 93
            B[ii] = sparse(vec(r), vec(c), vec(bas[:, 1:k-order[ii]+1]),
                           m, n-order[ii])  # 94 TODO: using vec might be slow

            # 96-100
            if order[ii] > 0
                B[ii] = B[ii] * D[order[ii]]
            elseif order[ii] < 0
                B[ii] = B[ii] * I[-order[ii]]
            end
        end
    end

    # 105
    if length(order) == 1
        B = B[1]
    end
    B, x
end
