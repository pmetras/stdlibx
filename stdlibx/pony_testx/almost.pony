primitive Almost
  fun eq[F: (Float & FloatingPoint[F])](a: F, b: F, rel_tol: F, abs_tol: F): Bool =>
    if a.nan() or b.nan() then
      false
    elseif a.infinite() or b.infinite() then
      a == b
    else
      let diff = (a - b).abs()
      let scale = rel_tol * a.abs().max(b.abs())
      diff <= scale.max(abs_tol)
    end
