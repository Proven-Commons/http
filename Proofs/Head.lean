/-
  The head: `parseHead` reads exactly `Spec.Reads`, and printing.
-/

import Http.Head
import Spec.Defs
import Proofs.Match
import Proofs.Lines
import Proofs.Fields

namespace Http.Proofs.Head

open Http

theorem requestTarget_eq : Grammar.requestTarget = Spec.requestTarget := rfl

theorem parseHead_iff (bs : List UInt8) (h : Head) (rest : List UInt8) :
    parseHead bs = some (h, rest) ↔ Spec.Reads bs h rest := by
  sorry

theorem print_eq (h : Head) : h.print = Spec.render h := by
  sorry

theorem parseHead_print (h : Head) (rest : List UInt8) (hv : Spec.HeadValid h) :
    parseHead (h.print ++ rest) = some (h, rest) := by
  sorry

end Http.Proofs.Head
