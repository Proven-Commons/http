/-
  Matching a string against a rule of the grammar notation, by
  Brzozowski derivatives: the derivative of a rule by an octet matches
  what can follow that octet. The constructors `mkCat` and `mkAlt` drop
  rules that match nothing, and `mkAlt` folds two kinds of repeat:
  `alt a a` is `a`, and `alt (alt x y) y` is `alt x y`. Without the
  second, each SP after a comma in a Transfer-Encoding list would add a
  level of `alt` to the derivative.

  Matching takes one derivative per octet. When a rule has finitely
  many derivatives, each takes bounded time, so matching takes time
  linear in the length of the string. Each rule the code matches, in
  `Http/Grammar.lean`, has finitely many: listing all the derivatives
  of each ends. That was checked by running the matcher, not proved.
-/

import Http.Abnf

namespace Http.Re

/-- Whether the rule matches the empty string. -/
def nullable : Re → Bool
  | empty => false
  | eps => true
  | range _ _ => false
  | cat a b => a.nullable && b.nullable
  | alt a b => a.nullable || b.nullable
  | star _ => true

/-- `cat`, simplified where one side matches nothing or only the empty
    string. -/
def mkCat : Re → Re → Re
  | empty, _ => empty
  | _, empty => empty
  | eps, b => b
  | a, eps => a
  | a, b => cat a b

/-- `alt`, simplified where one side matches nothing, where both are the
    same, or where the right one is already the right one of the left. -/
def mkAlt : Re → Re → Re
  | empty, b => b
  | a, empty => a
  | a, b =>
    if a = b then a
    else match a with
      | alt _ y => if y = b then a else alt a b
      | _ => alt a b

/-- What can follow the octet `c` in a string the rule matches. -/
def deriv (c : UInt8) : Re → Re
  | empty => empty
  | eps => empty
  | range lo hi => if lo ≤ c ∧ c ≤ hi then eps else empty
  | cat a b =>
    if a.nullable then mkAlt (mkCat (deriv c a) b) (deriv c b) else mkCat (deriv c a) b
  | alt a b => mkAlt (deriv c a) (deriv c b)
  | star a => mkCat (deriv c a) (star a)

/-- Whether the rule matches the string. -/
def isMatch (r : Re) : List UInt8 → Bool
  | [] => r.nullable
  | c :: cs => (r.deriv c).isMatch cs

end Http.Re
