/-
  Lines, empty lines, the three parts of the request line, and the
  version.
-/

import Http.Head
import Spec.Defs

namespace Http.Proofs.Lines

open Http

theorem takeLine_iff (bs l r : List UInt8) :
    takeLine bs = some (l, r) ↔ (0x0D ∉ l ∧ 0x0A ∉ l) ∧ bs = l ++ Spec.crlf ++ r := by
  sorry

theorem skipEmpty_crlf (k : Nat) (bs : List UInt8) :
    skipEmpty ((List.replicate k Spec.crlf).flatten ++ bs) = skipEmpty bs := by
  sorry

theorem skipEmpty_eq (bs : List UInt8) :
    ∃ k, bs = (List.replicate k Spec.crlf).flatten ++ skipEmpty bs := by
  sorry

theorem skipEmpty_cons (c : UInt8) (bs : List UInt8) (hc : c ≠ 0x0D) :
    skipEmpty (c :: bs) = c :: bs := by
  sorry

/-- What `skipEmpty` leaves does not start with CRLF. -/
theorem skipEmpty_head (bs rest : List UInt8) (h : skipEmpty bs = 0x0D :: 0x0A :: rest) : False := by
  sorry

theorem splitOn_three (m t v : List UInt8) (hm : 0x20 ∉ m) (ht : 0x20 ∉ t) (hv : 0x20 ∉ v) :
    (m ++ [0x20] ++ t ++ [0x20] ++ v).splitOn 0x20 = [m, t, v] := by
  sorry

theorem splitOn_three_inv (line m t v : List UInt8) (h : line.splitOn 0x20 = [m, t, v]) :
    line = m ++ [0x20] ++ t ++ [0x20] ++ v ∧ 0x20 ∉ m ∧ 0x20 ∉ t ∧ 0x20 ∉ v := by
  sorry

theorem parseVersion_iff (v : List UInt8) (a b : Nat) :
    parseVersion v = some (a, b) ↔
      a ≤ 9 ∧ b ≤ 9 ∧ v = Spec.ascii "HTTP/" ++ [Spec.digit a, 0x2E, Spec.digit b] := by
  sorry

end Http.Proofs.Lines
