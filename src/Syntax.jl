module Syntax
export
  BaseExpr, ObExpr, MorExpr, ob_expr, mor_expr, head, args,
  show_infix, show_latex, show_sexpr,
  dom, codom, id, compose, ∘, otimes, opow, munit, ⊗,
  braid, σ, mcopy, mmerge, create, delete, Δ, ∇, dual, ev, coev

using AutoHashEquals
using Match
using Typeclass

import ..Doctrine:
  Category, dom, codom, id, compose, ∘,
  MonoidalCategory, otimes, opow, munit, ⊗,
  SymmetricMonoidalCategory, braid, σ,
  InternalMonoid, InternalComonoid, mcopy, mmerge, create, delete, Δ, ∇,
  CompactClosedCategory, dual, ev, coev

# Expressions
#############

""" Base type for expressions in categorical languages.

We define Julia types for each "kind" or "metatype" in the language: currently
*object* and *morphism*, perhaps later *2-morphism*, *3-morphism*, etc. The
concrete types are structurally similar to the core type `Expr` in Julia.

**Design note**: An alternative approach would represent every kind with the
`Expr` type, using its `typ` field to distinguish objects and morphisms. I think
that would be a mistake. It would conflate the `Ob` and `Mor` type parameters in
the type classes. More fundamentally, it is always wrong to change the kind of
an expression at the syntactic level, e.g., any rewrite rule that transforms an
object expression to a morphism expression makes a category error. We should
enforce this constraint at the type level in Julia.

At the other extreme, we could create a concrete type for each syntactic element
(`GeneratorMor`, `IdMor`, `CompositeMor`, etc). This idea is better than the
last but leads to a large proliferation of types and makes it inconvenient to
write generic code operating on expressions as a homogeneous data structure
(analogous to S-expressions).
"""
abstract BaseExpr

@auto_hash_equals immutable ObExpr <: BaseExpr
  head::Symbol
  args::Vector
  ObExpr(head, args...) = new(head, [args...])
end

@auto_hash_equals immutable MorExpr <: BaseExpr
  head::Symbol
  args::Vector
  MorExpr(head, args...) = new(head, [args...])
end

# Generators
ob_expr(A::Symbol) = ObExpr(:gen, A)
mor_expr(f::Symbol, dom::ObExpr, codom::ObExpr) = MorExpr(:gen, f, dom, codom)

# Accessors and operators
head(expr::BaseExpr)::Symbol = expr.head
args(expr::BaseExpr)::Vector = expr.args

""" Apply associative binary operation to two expressions.

Maintains the normal form E(:op, [e1,e2,..]) where e1,e2,... are expressions
that are *not* applications of :op.
"""
function associate{E<:BaseExpr}(op::Symbol, e1::E, e2::E)
  terms(expr::E) = head(expr) == op ? args(expr) : [expr]
  E(op, [terms(e1);terms(e2)]...)
end

# Category
##########

@doc """ Syntax for a *category*.

Although they implement the `Category` typeclass, the expressions do not
strictly speaking form a category because they don't satisfy the category laws,
e.g.,
```
compose(f, id(A)) != compose(f)
```
The expressions form a *syntax* for categories. Equational reasoning and the
conversion to normal form are handled by other components. (An exception is the
associativity of composition, which for convenience is handled at the syntactic
level.) Similar remarks apply to the other doctrines.
""" CategorySyntax

@instance! Category ObExpr MorExpr begin
  dom(f::MorExpr) = dom(f, Val{head(f)})
  codom(f::MorExpr) = codom(f, Val{head(f)})
  id(A::ObExpr) = MorExpr(:id, A)

  function compose(f::MorExpr, g::MorExpr)
    if codom(f) != dom(g)
      error("Incompatible domains $(codom(f)) and $(dom(f))")
    end
    associate(:compose, f, g)
  end
end

dom(f::MorExpr, ::Type{Val{:gen}}) = args(f)[2]
codom(f::MorExpr, ::Type{Val{:gen}}) = args(f)[3]

dom(f::MorExpr, ::Type{Val{:compose}}) = dom(first(args(f)))
codom(f::MorExpr, ::Type{Val{:compose}}) = codom(last(args(f)))

dom(f::MorExpr, ::Type{Val{:id}}) = args(f)[1]
codom(f::MorExpr, ::Type{Val{:id}}) = args(f)[1]

# Monoidal category
###################

@doc """ Syntax for a (strict) *monoidal category*.

To satisfy the strictness requirement, monoidal products of objects are
automatically brought to normal form. No other equational reasoning is performed
at the syntactic level.
""" MonoidalCategorySyntax

@instance! MonoidalCategory ObExpr MorExpr begin
  function otimes(A::ObExpr, B::ObExpr)
    @match (A, B) begin
      (ObExpr(:unit,_), _) => B
      (_, ObExpr(:unit,_)) => A
      _ => associate(:otimes, A, B)
    end
  end
  otimes(f::MorExpr, g::MorExpr) = associate(:otimes, f, g)
  munit(::ObExpr) = ObExpr(:unit)
end

dom(f::MorExpr, ::Type{Val{:otimes}}) = otimes(map(dom, args(f))...)
codom(f::MorExpr, ::Type{Val{:otimes}}) = otimes(map(codom, args(f))...)

# Symmetric monoidal category
#############################

@instance! SymmetricMonoidalCategory ObExpr MorExpr begin
  braid(A::ObExpr, B::ObExpr) = MorExpr(:braid, A, B)
end

dom(f::MorExpr, ::Type{Val{:braid}}) = otimes(args(f)[1], args(f)[2])
codom(f::MorExpr, ::Type{Val{:braid}}) = otimes(args(f)[2], args(f)[1])

# Internal (co)monoid
#####################

@instance! InternalMonoid ObExpr MorExpr begin
  mmerge(A::ObExpr) = MorExpr(:merge, A)
  create(A::ObExpr) = MorExpr(:create, A)
end

@instance! InternalComonoid ObExpr MorExpr begin
  mcopy(A::ObExpr) = MorExpr(:copy, A)
  delete(A::ObExpr) = MorExpr(:delete, A)
end

dom(f::MorExpr, ::Type{Val{:copy}}) = args(f)[1]
codom(f::MorExpr, ::Type{Val{:copy}}) = opow(args(f)[1], 2)

dom(f::MorExpr, ::Type{Val{:merge}}) = opow(args(f)[1], 2)
codom(f::MorExpr, ::Type{Val{:merge}}) = args(f)[1]

dom(f::MorExpr, ::Type{Val{:create}}) = munit(args(f)[1])
codom(f::MorExpr, ::Type{Val{:create}}) = args(f)[1]

dom(f::MorExpr, ::Type{Val{:delete}}) = args(f)[1]
codom(f::MorExpr, ::Type{Val{:delete}}) = munit(args(f)[1])

# Compact closed category
#########################

@instance! CompactClosedCategory ObExpr MorExpr begin
  dual(A::ObExpr) = ObExpr(:dual, A)
  ev(A::ObExpr) = MorExpr(:eval, A)
  coev(A::ObExpr) = MorExpr(:coeval, A)
end

dom(f::MorExpr, ::Type{Val{:eval}}) = otimes(args(f)[1], dual(args(f)[1]))
codom(f::MorExpr, ::Type{Val{:eval}}) = munit(args(f)[1])

dom(f::MorExpr, ::Type{Val{:coeval}}) = munit(args(f)[1])
codom(f::MorExpr, ::Type{Val{:coeval}}) = otimes(dual(args(f)[1]), args(f)[1])

# Pretty-print
##############

""" Show the expression as an S-expression.

The transformation is *not* one-to-one since the domains and codomains are
discarded.

Cf. the standard library function `Meta.show_sexpr`.
"""
show_sexpr(expr::BaseExpr) = show_expr(STDOUT, expr)
show_sexpr(io::IO, expr::BaseExpr) = print(io, as_sexpr(expr))

function as_sexpr(expr::BaseExpr)::String
  if head(expr) == :gen
    repr(args(expr)[1])
  else
    string("(", join([head(expr), map(as_sexpr,args(expr))...], " "), ")")
  end
end

""" Show the expression in infix notation using Unicode symbols.
"""
show_infix(expr::BaseExpr) = show_infix(STDOUT, expr)
show_infix(io::IO, expr::BaseExpr) = print(io, as_infix(expr))

function as_infix(expr::BaseExpr; paren::Bool=false)::String
  head, args = Syntax.head(expr), Syntax.args(expr)
  if head == :gen # special case: generator
    return string(args[1])
  end

  symbol = get(symbol_table_unicode, head, string(head))
  if length(symbol) <= 1 && length(args) >= 2 # case 1: infix
    result = join((as_infix(a;paren=true) for a in args), symbol)
    paren ? "($result)" : result
  elseif length(args) >= 1 # case 2: prefix
    string(symbol, "[", join(map(as_infix, args), ","), "]")
  else # degenerate case: no arguments
    symbol
  end
end

const symbol_table_unicode = Dict{Symbol,String}(
  :compose => " ",
  :otimes => "⊗",
  :unit => "I",
)

""" Show the expression in infix notation using LaTeX math.

Does *not* include `\$` or `\\[begin|end]{equation}` delimiters.
"""
show_latex(expr::BaseExpr) = show_latex(STDOUT, expr)
show_latex(io::IO, expr::BaseExpr) = print(io, as_latex(expr))

as_latex(expr::BaseExpr; kw...) = as_latex(expr, Val{head(expr)}; kw...)
as_latex(expr::BaseExpr, ::Type{Val{:gen}}; kw...) = string(first(args(expr)))

# Category
function as_latex(id::MorExpr, ::Type{Val{:id}}; kw...)
  subscript("\\mathrm{id}", as_latex(dom(id)))
end
function as_latex(expr::MorExpr, ::Type{Val{:compose}}; paren::Bool=false, kw...)
  binary_op(expr, " ", paren)
end

# Monoidal category
as_latex(::ObExpr, ::Type{Val{:unit}}; kw...) = "I"
function as_latex(expr::BaseExpr, ::Type{Val{:otimes}}; paren::Bool=false, kw...)
  binary_op(expr, "\\otimes", paren)
end

# Symmetric monoidal category
function as_latex(expr::MorExpr, ::Type{Val{:braid}}; kw...)
  subscript("\\sigma", join(map(as_latex, args(expr)), ","))
end

# Internal (co)monoid
function as_latex(expr::MorExpr, ::Type{Val{:copy}}; kw...)
  subscript("\\Delta", as_latex(dom(expr)))
end
function as_latex(expr::MorExpr, ::Type{Val{:delete}}; kw...)
  subscript("e", as_latex(dom(expr)))
end
function as_latex(expr::MorExpr, ::Type{Val{:merge}}; kw...)
  subscript("\\nabla", as_latex(codom(expr)))
end
function as_latex(expr::MorExpr, ::Type{Val{:create}}; kw...)
  subscript("i", as_latex(codom(expr)))
end

# Closed compact category
function as_latex(expr::ObExpr, ::Type{Val{:dual}}; kw...)
  supscript(as_latex(first(args(expr))), "*")
end
function as_latex(expr::MorExpr, ::Type{Val{:eval}}; kw...)
  subscript("\\mathrm{ev}", as_latex(first(args(expr))))
end
function as_latex(expr::MorExpr, ::Type{Val{:coeval}}; kw...)
  subscript("\\mathrm{coev}", as_latex(first(args(expr))))
end

subscript(body::String, sub::String) = "$(body)_{$sub}"
supscript(body::String, sup::String) = "$(body)^{$sup}"

function binary_op(expr::BaseExpr, op::String, paren::Bool)
  sep = op == " " ? op : " $op "
  result = join((as_latex(a;paren=true) for a in args(expr)), sep)
  paren ? "\\left($result\\right)" : result
end

end