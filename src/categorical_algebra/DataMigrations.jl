""" Functorial data migration for attributed C-sets.
"""
module DataMigrations
export DataMigration, DeltaMigration, SigmaMigration, migrate, migrate!

using ...Syntax, ...Present, ...Theories
using ...Theories: SchemaDesc, ob, hom, dom, codom, attr, adom
using ..Categories, ..FinCats, ..Limits, ..Diagrams, ..FinSets, ..CSets
using ...Graphs, ..FreeDiagrams
import ..Categories: ob_map, hom_map
using ..FinCats: make_map, mapvals

# Data types
############

""" Conjunctive query over schema ``C``.

The diagram comprising the query specifies a finite limit.
"""
const ConjQuery{C<:FinCat} = Diagram{op,C}

""" Gluing or agglomerative query over schema ``C``.

The diagram comprising the query specifies a finite colimit. In the important
special case that the diagram has discrete shape, it specifies a finite
coproduct and the query is called "linear" or "disjunctive".
"""
const GlueQuery{C<:FinCat} = Diagram{id,C}

""" "Gluc query" (gluing of conjunctive queries) over schema ``C``.

The diagram of diagrams comprising the query specifies a finite colimit of
finite limits. In the important special case that the outer diagram has discrete
shape, it specifies a finite coproduct of finite limits and the query is called
a "duc query" (disjoint union of conjunctive queries).
"""
const GlucQuery{C<:FinCat} = Diagram{id,<:TypeCat{<:Diagram{op,C}}}

""" Functor defining a pullback or delta data migration.
"""
const DeltaSchemaMigration{D<:FinCat,C<:FinCat} = FinFunctor{D,C}

""" Functor defining a contravariant data migration using conjunctive queries.
"""
const ConjSchemaMigration{D<:FinCat,C<:FinCat} =
  FinDomFunctor{D,<:TypeCat{<:ConjQuery{C}}}

""" Functor defining a contravariant data migration using gluing queries.
"""
const GlueSchemaMigration{D<:FinCat,C<:FinCat} =
  FinDomFunctor{D,<:TypeCat{<:GlueQuery{C}}}

""" Functor defining a contravariant data migration using gluc queries.
"""
const GlucSchemaMigration{D<:FinCat,C<:FinCat} =
  FinDomFunctor{D,<:TypeCat{<:GlucQuery{C}}}

""" Abstract type for a data migration functor.
"""
abstract type MigrationFunctor{Dom<:ACSet,Codom<:ACSet} <:
  Functor{TypeCat{Dom,ACSetTransformation},TypeCat{Codom,ACSetTransformation}} end

ob_map(F::MigrationFunctor{Dom,Codom}, X::Dom) where {Dom,Codom} =
  ob_map(F, Codom, X)

(F::MigrationFunctor)(X::ACSet) = ob_map(F, X)
(F::MigrationFunctor)(α::ACSetTransformation) = hom_map(F, α)

""" Data migration functor given contravariantly.

This type encompasses data migration functors from ``C``-sets to ``D``-sets
given contravariantly by a functor out of the schema ``D``. The simplest such
functor is a pullback data migration ([`DeltaMigration`](@ref)), specified by a
functor ``D → C`` between the schemas. Other important cases include conjunctive
and duc data migrations.
"""
struct DataMigration{Dom,Codom,F<:FinDomFunctor} <: MigrationFunctor{Dom,Codom}
  functor::F
end

DataMigration(functor::F, ::Type{Dom}, ::Type{Codom}) where {F,Dom,Codom} =
  DataMigration{Dom,Codom,F}(functor)
DataMigration(functor::F, ::Type{Codom}) where {F,Codom} =
  DataMigration{ACSet,Codom,F}(functor)

ob_map(F::DataMigration, T::Type, X) = migrate(T, X, F.functor)

""" Delta or pullback functorial data migration between acsets.

Given a functor ``F: D → C``, the delta migration functor ``Δ_F`` from
``C``-sets to ``D``-sets is defined contravariantly by ``Δ_F(X) := X ∘ F``.

See (Spivak, 2014, *Category Theory for the Sciences*) for details.
"""
const DeltaMigration{Dom,Codom} = DataMigration{Dom,Codom,<:DeltaSchemaMigration}

DeltaMigration(args...) = DataMigration(args...)::DeltaMigration

const ConjMigration{Dom,Codom} = DataMigration{Dom,Codom,<:ConjSchemaMigration}
const GlueMigration{Dom,Codom} = DataMigration{Dom,Codom,<:GlueSchemaMigration}
const GlucMigration{Dom,Codom} = DataMigration{Dom,Codom,<:GlucSchemaMigration}

# Contravariant migration
#########################

""" Contravariantly migrate data from the acset `Y` to a new acset of type `T`.

The mutating variant of this function is [`migrate!`](@ref).
"""
function migrate(::Type{T}, X::ACSet, F::FinDomFunctor; kw...) where T <: ACSet
  T(migrate(X, F; kw...))
end
function migrate(X::ACSet, F::FinDomFunctor; kw...)
  migrate(FinDomFunctor(X), F; kw...)
end

""" Contravariantly migrate data from the acset `Y` to the acset `X`.

This is the mutating variant of [`migrate!`](@ref). When the functor on schemas
is the identity, this operation is equivalent to [`copy_parts!`](@ref).
"""
function migrate!(X::ACSet, Y::ACSet, F::FinDomFunctor; kw...)
  copy_parts!(X, migrate(Y, F; kw...))
end

# Delta migration
#----------------

migrate(::Type{T}, X::ACSet, F::DeltaSchemaMigration) where T <: ACSet =
  migrate!(T(), X, F)
migrate(::Type{T}, X::ACSet, FOb, FHom) where T <: ACSet =
  migrate!(T(), X, FOb, FHom)

function migrate!(X::StructACSet{S}, Y::ACSet, F::DeltaSchemaMigration) where S
  partsX = Dict(c => add_parts!(X, c, nparts(Y, nameof(ob_map(F,c))))
                for c in ob(S))
  for (f,c,d) in zip(hom(S), dom(S), codom(S))
    set_subpart!(X, partsX[c], f, partsX[d][subpart(Y, hom_map(F,f))])
  end
  for (f,c) in zip(attr(S), adom(S))
    set_subpart!(X, partsX[c], f, subpart(Y, hom_map(F,f)))
  end
  return X
end

function migrate!(X::ACSet, Y::ACSet, FOb, FHom)
  F = FinFunctor(FOb, FHom, FinCat(Presentation(X)), FinCat(Presentation(Y)))
  migrate!(X, Y, F)
end

function (::Type{T})(X::ACSet, F::FinFunctor) where T <: ACSet
  Base.depwarn("Data migration constructor is deprecated, use `migrate` instead", :ACSet)
  migrate(T, X, F)
end

function (::Type{T})(X::ACSet, FOb::AbstractDict, FHom::AbstractDict) where T <: ACSet
  Base.depwarn("Data migration constructor is deprecated, use `migrate` instead", :ACSet)
  migrate(T, X, FOb, FHom)
end

# Conjunctive migration
#----------------------

function migrate(X::FinDomFunctor, F::ConjSchemaMigration;
                 return_limits::Bool=false, tabular::Bool=false)
  tgt_schema = dom(F)
  limits = make_map(ob_generators(tgt_schema)) do c
    Fc = ob_map(F, c)
    # XXX: Disable domain check because acsets don't store schema equations.
    lim = limit(compose(Fc, X, strict=false),
                alg=SpecializeLimit(fallback=ToBipartiteLimit()))
    if tabular
      J = shape(Fc)
      TabularLimit(lim, names=(ob_name(J, j) for j in ob_generators(J)))
    else
      lim
    end
  end
  funcs = make_map(hom_generators(tgt_schema)) do f
    Ff, c, d = hom_map(F, f), dom(tgt_schema, f), codom(tgt_schema, f)
    # XXX: Disable domain check for same reason.
    universal(compose(Ff, X, strict=false), limits[c], limits[d])
  end
  Y = FinDomFunctor(mapvals(ob, limits), funcs, tgt_schema)
  return_limits ? (Y, limits) : Y
end

# FIXME: We should put this elsewhere and think more carefully about names.
ob_name(C::FinCat, x) = x
ob_name(C::FinCat, x::GATExpr) = nameof(x)
hom_name(C::FinCat, f) = f
hom_name(C::FinCat, f::GATExpr) = nameof(f)
ob_named(C::FinCat, name) = ob(C, name)
hom_named(C::FinCat, name) = hom(C, name)

# Gluing migration
#-----------------

function migrate(X::FinDomFunctor, F::GlueSchemaMigration)
  tgt_schema = dom(F)
  colimits = make_map(ob_generators(tgt_schema)) do c
    Fc = ob_map(F, c)
    # XXX: Force composition to tighten the codomain types.
    colimit(force(compose(Fc, X, strict=false)), alg=SpecializeColimit())
  end
  funcs = make_map(hom_generators(tgt_schema)) do f
    Ff, c, d = hom_map(F, f), dom(tgt_schema, f), codom(tgt_schema, f)
    universal(compose(Ff, X, strict=false), colimits[c], colimits[d])
  end
  FinDomFunctor(mapvals(ob, colimits), funcs, tgt_schema)
end

# Gluc migration
#---------------

function migrate(X::FinDomFunctor, F::GlucSchemaMigration)
  tgt_schema = dom(F)
  colimits_of_limits = make_map(ob_generators(tgt_schema)) do c
    Fc = ob_map(F, c)
    Fc_set, limits = migrate(X, diagram(Fc), return_limits=true)
    (colimit(Fc_set), Fc_set, limits)
  end
  funcs = make_map(hom_generators(tgt_schema)) do f
    Ff, c, d = hom_map(F, f), dom(tgt_schema, f), codom(tgt_schema, f)
    Fc_colim, Fc_set, Fc_limits = colimits_of_limits[c]
    Fd_colim, Fd_set, Fd_limits = colimits_of_limits[d]
    component_funcs = map(ob_generators(dom(Fc_set))) do j
      j′, Ffⱼ = ob_map(Ff, j)
      universal(compose(Ffⱼ, X, strict=false), Fc_limits[j], Fd_limits[j′])
    end
    Ff_set = DiagramHom{id}(shape_map(Ff), component_funcs, Fc_set, Fd_set)
    universal(Ff_set, Fc_colim, Fd_colim)
  end
  FinDomFunctor(mapvals(ob∘first, colimits_of_limits), funcs, tgt_schema)
end

# Sigma migration
#################

""" Sigma or left pushforward functorial data migration between acsets.

Given a functor ``F: C → D``, the sigma data migration ``Σ_F`` is a functor from
``C``-sets to ``D``-sets that is left adjoint to the delta migration functor
``Δ_F`` ([`DeltaMigration`](@ref)). Explicitly, the ``D``-set ``Σ_F(X)`` is
given on objects ``d ∈ D`` by the formula ``Σ_F(x)(d) = \\mathrm{colim}_{F ↓ d}
X ∘ π``, where ``π: (F ↓ d) → C`` is the projection.

See (Spivak, 2014, *Category Theory for the Sciences*) for details.
"""
struct SigmaMigration{Dom,Codom,F<:FinFunctor,CC} <: MigrationFunctor{Dom,Codom}
  functor::F
  comma_cats::CC

  function SigmaMigration(functor::F, ::Type{Dom}, ::Type{Codom}) where
      {F<:FinFunctor, Dom, Codom}
    comma_cats = get_comma_cats(functor)
    new{Dom,Codom,F,typeof(comma_cats)}(functor, comma_cats)
  end
end

SigmaMigration(functor::FinFunctor, ::Type{Codom}) where Codom =
  SigmaMigration(ACSet, Codom, functor)

function ob_map(ΣF::SigmaMigration, ::Type{T}, X::ACSet) where T <: ACSet
  comma_cats = ΣF.comma_cats
  diagramD = FreeDiagram(presentation(codom(ΣF.functor)))

  # define Y on objects by taking colimits
  Y = T()
  colimX = map(parts(diagramD, :V)) do i
    F∇d = ob(comma_cats, i)
    Xobs = map(ob(F∇d)) do (c,_)
      FinSet(X, nameof(c))
    end
    Xhoms = map(parts(F∇d, :E)) do g
      FinFunction(X, nameof(hom(F∇d, g)))
    end
    colimit(FreeDiagram(Xobs, collect(zip(Xhoms, src(F∇d), tgt(F∇d)))))
  end

  for d in parts(diagramD, :V)
    add_parts!(Y, nameof(ob(diagramD, d)), length(apex(colimX[d])))
  end
  
  # Define Y on morphisms by the universal property
  for g in parts(diagramD, :E)
    if nparts(Y, nameof(dom(hom(diagramD, g)))) == 0
      continue
    end
    set_subpart!(Y, nameof(hom(diagramD, g)),
      collect(universal(colimX[src(diagramD, g)],
        Multicospan(legs(colimX[tgt(diagramD, g)])[collect(hom(comma_cats, g)[:V])])
      )))
  end
  return Y
end

""" add_hom!(d::FreeDiagram{Ob, Hom}, src_ob::Ob, tgt_ob::Ob, hom::Hom)

Adds a hom to `d` from the vertex with object `src_ob` to the vertex with object `tgt_ob`.
"""
function add_hom!(d::FreeDiagram, src_ob, tgt_ob, hom) 
  src_idx = first(incident(d, src_ob, :ob))
  tgt_idx = first(incident(d, tgt_ob, :ob))
  return add_edge!(d, src_idx, tgt_idx, hom = hom)
end

"""   comma_cats(diagramD::FreeDiagram{FreeSchema.Ob, FreeSchema.Hom}, FOb, FHom)

Given a free category ``\\mathcal{D}`` with no cycles and 
a functor represented by the pair `(FOb, FHom)`, returns a diagram 
``\\mathcal{D} \\to \\mathsf{Cat}`` which on objects takes ``d \\in \\mathcal{D}`` to the 
comma category ``F \\downarrow d``.
"""
function get_comma_cats(F::FinFunctor)
  diagramD = FreeDiagram(presentation(codom(F)))
  FObInv = y -> filter(x -> ob_map(F,x) == y, ob_generators(dom(F)))
  FHomInv = g -> filter(f -> hom_map(F,f) == g, hom_generators(dom(F)))
  comma_cats = FreeDiagram{FreeDiagram, ACSetTransformation}()
  add_vertices!(comma_cats,
    nparts(diagramD, :V), 
    ob = map(parts(diagramD, :V)) do _
      FreeDiagram{Pair{FreeSchema.Ob, FreeSchema.Hom}, FreeSchema.Hom}() 
    end
  )

  for d in topological_sort(diagramD)
    F∇d = ob(comma_cats, d)
    id_d = id(ob(diagramD, d))

    # If FOb[c] = d, add an objects (c, id(d)) to F∇d
    preimage_d = FObInv(ob(diagramD, d)) 
    id_obs = add_vertices!(F∇d, length(preimage_d), ob = map(c->c=>id_d, preimage_d))
    
    # if FHom[h] = id(d), add a hom h: (dom(h), id(d)) -> (codom(h), id(d)) to F∇d 
    id_homs = map(FHomInv(id_d)) do h
      add_hom!(F∇d, dom(h) => id_d, codom(h) => id_d, h)
    end

    # for g: d' -> d in D (note that F∇d' must have already been constructed)
    #     populate F∇d with obs and homs coming from F∇d′
    for g in incident(diagramD, d, :tgt)
      d′ = src(diagramD, g)
      F∇g = comma_cat_hom!(F∇d, ob(comma_cats, d′), id_d, hom(diagramD, g), FHomInv)
      add_edge!(comma_cats, d′, d, hom=F∇g)      
    end 
  end

  return comma_cats
end

function comma_cat_hom!(F∇d, F∇d′, id_d, g, FHomInv)
  # for (c,f) in F∇d' add ob (c, compose(f,g)) to F∇d
  vs = add_vertices!(F∇d, nparts(F∇d′, :V), ob = map(ob(F∇d′)) do (c,f)
    c => compose(f, g)                
  end)

  # for h: (c, f) -> (c', f') in diagram_d', add hom h to F∇d    
  es = add_edges!(F∇d, vs[src(F∇d′)], vs[tgt(F∇d′)], hom = hom(F∇d′))

  # for every (c,f) in the recently added objects. If FHom[h] == f, then add the hom 
  #       h: (c,f) -> (codom(h), idv)
  # relies on D being free
  for (c, f) in ob(F∇d, vs)
    for h in FHomInv(f)
      dom(h) == c && add_hom!(F∇d, c => f, codom(h) => id_d, h)
    end
  end

  # return the inclusion from F∇d′ to F∇d 
  return ACSetTransformation((V = collect(vs), E = collect(es)), F∇d′, F∇d)
end

# Schema translation
####################

# FIXME: This function does not belong here.

"""   FreeDiagram(pres::Presentation{FreeSchema, Symbol})

Returns a `FreeDiagram` whose objects are the generating objects of `pres` and 
whose homs are the generating homs of `pres`.
"""
function FreeDiagrams.FreeDiagram(pres::Presentation{Schema, Symbol}) where Schema
  obs = Array{FreeSchema.Ob}(generators(pres, :Ob))
  homs = Array{FreeSchema.Hom}(generators(pres, :Hom))
  doms = map(h -> generator_index(pres, nameof(dom(h))), homs)
  codoms = map(h -> generator_index(pres, nameof(codom(h))), homs)
  return FreeDiagram(obs, collect(zip(homs, doms, codoms)))
end

end
