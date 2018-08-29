# utilities

function tensorcontractmatrix(tnsr::StridedArray{T,N}, mtx::Matrix{T}, n::Int;
                              transpose::Bool=false, method::Symbol=:BLAS) where {T,N}
    #info("TTM: tnsr=$(size(tnsr)) mtx=$(size(mtx)) n=$n transpose=$transpose method=$method")
    tensorcontract(tnsr, 1:N,
                   mtx, [transpose ? N+1 : n, transpose ? n : N+1],
                   [1:(n-1); N+1; (n+1):N], method=method)
end

function tensorcontractmatrix!(dest::StridedArray{T,N}, src::StridedArray{T,N},
                               mtx::Matrix{T}, n::Int; transpose::Bool=false, method::Symbol=:BLAS) where {T,N}
    #info("TTM: dest=$(size(dest)) src=$(size(src)) mtx=$(size(mtx)) n=$n transpose=$transpose method=$method")
    tensorcontract!(1, src, 1:N, 'N',
                    mtx, [transpose ? N+1 : n, transpose ? n : N+1], 'N',
                    0, dest, [1:(n-1); N+1; (n+1):N], method=method)
end

"""
Contract N-mode tensor and M matrices.

  * `dest` array to hold the result
  * `src`  source tensor to contract
  * `matrices` matrices to contract
  * `modes` corresponding modes of matrices to contract
  * `transpose` if true, matrices are contracted along their columns
"""
function tensorcontractmatrices!(dest::Array{T,N}, src::Array{T,N}, matrices::Any,
                                 modes::Any = 1:length(matrices);
                                 transpose::Bool=false, method::Symbol=:BLAS) where {T,N}
    for mtx_ix in 1:length(matrices)-1
        src = tensorcontractmatrix(src, matrices[mtx_ix], modes[mtx_ix],
                                   transpose=transpose, method=method)
    end
    tensorcontractmatrix!(dest, src, matrices[end], modes[end],
                          transpose=transpose, method=method)
end

"""
Contract N-mode tensor and M matrices.

  * `tensor` tensor to contract
  * `matrices` matrices to contract
  * `modes` corresponding modes of matrices to contract
  * `transpose` if true, matrices are contracted along their columns
"""
tensorcontractmatrices(tensor::Array{T,N}, matrices::Any,
                       modes::Any = 1:length(matrices);
                       transpose::Bool=false, method::Symbol=:BLAS) where {T,N} =
    reduce(tensor, 1:length(matrices)) do tnsr, mtx_ix
        tensorcontractmatrix(tnsr, matrices[mtx_ix], modes[mtx_ix],
                             transpose=transpose, method=method)
    end

"""
Generates random factor matrices for Tucker/CANDECOMP etc decompositions.

  * `orig_dims` original tensor dimensions
  * `core_dims` core tensor dimensions

Returns:
  * a vector of `N` (orig[n], core[n])-sized matrices
"""
_random_factors(orig_dims::NTuple{N, Int}, core_dims::NTuple{N, Int}) where {N} =
    Matrix{Float64}[randn(o_dim, c_dim) for (o_dim, c_dim) in zip(orig_dims, core_dims)]

"""
Generates random factor matrices for Tucker/CANDECOMP decompositions if core tensor is `r^N` hypercube.

Returns:
  * a vector of `N` (orig[n], r)-sized matrices
"""
_random_factors(dims::NTuple{N, Int}, r::Integer) where {N} =
    _random_factors(dims, ntuple(_ -> r, N))

"""
Calculates Khatri-Rao product of two matrices (column-wise Kronecker product).
"""
function khatrirao(A::Matrix{T}, B::Matrix{T}) where T
    size(A, 2) == size(B, 2) || throw(DimensionMismatch("Input matrices should have the same number of columns."))
    res = Matrix{T}(size(A, 1) * size(B, 1), size(A, 2))
    for i in 1:size(A, 2)
        res[:, i] = kron(A[:, i], B[:, i])
    end
    return res
end

"""
Unfolds the tensor into matrix, such that the specified
group of modes becomes matrix rows and the other one becomes columns.

  * `row_modes` vector of modes to be unfolded as rows
  * `col_modes` vector of modes to be unfolded as columns
"""
function _unfold(tnsr::StridedArray{T,N}, row_modes::Vector{Int}, col_modes::Vector{Int}) where {T,N}
    length(row_modes) + length(col_modes) == N ||
        throw(ArgumentError("column and row modes should be disjoint subsets of 1:N"))

    dims = size(tnsr)
    return reshape(permutedims(tnsr, [row_modes; col_modes]),
                   prod(dims[row_modes]), prod(dims[col_modes]))
end

"""
Unfolds the tensor into matrix such that the specified mode becomes matrix row.
"""
_row_unfold(tnsr::StridedArray{T,N}, mode::Integer) where {T,N} =
    _unfold(tnsr, [mode], [1:mode-1; mode+1:N])

"""
Unfolds the tensor into matrix such that the specified mode becomes matrix column.
"""
_col_unfold(tnsr::StridedArray{T,N}, mode::Integer) where {T,N} =
    _unfold(tnsr, [1:mode-1; mode+1:N], [mode])

function _iter_status(converged::Bool, niters::Integer, maxiter::Integer)
    converged ? info("Algorithm converged after $(niters) iterations.") :
                warn("Maximum number $(maxiter) of iterations exceeded.")
end

_check_sign(v::StridedVector) = sign(v[findmax(abs.(v))[2]]) * v

"""
Checks the validity of the core tensor dimensions.
"""
function _check_tensor(tnsr::StridedArray{T, N}, core_dims::NTuple{N, Int}) where {T<:Real,N}
    ndims(tnsr) > 2 || throw(ArgumentError("This method does not support scalars, vectors, or matrices input."))
    for i in 1:N
      0 < core_dims[i] <= size(tnsr, i) || throw(ArgumentError("core_dims[$i]=$(core_dims[i]) given, 1 <= core_dims[$i] <= size(tensor, $i) = $(size(tnsr, i)) expected."))
    end
    #isreal(T) || throw(ArgumentError("This package currently only supports real-number-valued tensors."))
    return N
end

"""
Checks the validity of the core tensor dimensions, where core tensor is `r^N` hypercube.
"""
_check_tensor(tensor::StridedArray{T, N}, r::Integer) where {T<:Real,N} =
    _check_tensor(tensor, ntuple(_ -> r, N))
