#include <algorithm>
#include <cmath>
#include <iostream>

#include <ginkgo/ginkgo.hpp>


int main()
{
    using vec = gko::matrix::Dense<double>;
    using mtx = gko::matrix::Csr<double, int>;
    using cg = gko::solver::Cg<double>;

    // Prints the core version and every backend that was compiled in.
    std::cout << gko::version_info::get() << std::endl;

    auto exec = gko::ReferenceExecutor::create();

    // 1D Laplacian, the solution of A x = A 1 is x = 1.
    const gko::size_type n = 16;
    gko::matrix_data<double, int> data{gko::dim<2>{n, n}};
    for (int i = 0; i < static_cast<int>(n); ++i) {
        if (i > 0) {
            data.nonzeros.emplace_back(i, i - 1, -1.0);
        }
        data.nonzeros.emplace_back(i, i, 2.0);
        if (i < static_cast<int>(n) - 1) {
            data.nonzeros.emplace_back(i, i + 1, -1.0);
        }
    }
    auto A = gko::share(mtx::create(exec));
    A->read(data);

    auto ones = vec::create(exec, gko::dim<2>{n, 1});
    ones->fill(1.0);
    auto b = vec::create(exec, gko::dim<2>{n, 1});
    A->apply(ones, b);
    auto x = vec::create(exec, gko::dim<2>{n, 1});
    x->fill(0.0);

    cg::build()
        .with_criteria(gko::stop::Iteration::build().with_max_iters(100u),
                       gko::stop::ResidualNorm<double>::build()
                           .with_reduction_factor(1e-12))
        .on(exec)
        ->generate(A)
        ->apply(b, x);

    double max_err = 0.0;
    for (gko::size_type i = 0; i < n; ++i) {
        max_err = std::max(max_err, std::abs(x->at(i, 0) - 1.0));
    }
    std::cout << "max error: " << max_err << std::endl;
    return max_err < 1e-8 ? 0 : 1;
}
