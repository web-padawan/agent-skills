# Where moved code belongs in a mixin chain

A component composes its behavior from a chain of mixins. The members of one component family
apply different subsets of that chain. One member often applies only the base mixin, while
another applies the base plus several richer mixins. A shared child element, such as a list
scroller or an item, is driven by one mixin that every member reuses. That child holds a
reference to its host and calls methods on it.

This layout decides where a moved method can live. Work through the rules in order.

## Rule 1 — A method that a child calls belongs to the lowest common mixin

Find every host that the shared child serves. The method must exist on the lowest mixin that
all of those hosts apply.

A host that applies fewer mixins fails at run time when the method is missing. The failure is a
type error on every render of an item. No type check and no lint rule reports it first, because
the call goes through a plain object reference.

A host that fails this rule carries a bug today. Probe the value on each host before you plan
anything.

## Rule 2 — Split a neutral default from an override

A method often reads a property that a richer mixin declares. The base mixin must not read a
property that it does not declare.

Put a neutral default in the base mixin. Put the override in the mixin that declares the
property. The override calls the base through `super`.

The codebase usually holds an existing pair of getters that use this split. Find one and follow
the same shape, so that a reader recognizes it.

## Rule 3 — Placement decides the public API

A public method in a lower mixin reaches every component that applies that mixin. Ask one
question before you move it. Should the component that applies the fewest mixins gain this
method?

If the answer is no, use the higher mixin. A method that only the richer components need does
not belong to the base, even when the base would accept it.

A property declaration follows the same rule. When two hosts declare the same property with the
same options, move the declaration to the shared mixin. Remove it from both hosts and from both
type definition files.

## Rule 4 — Prove the placement with a run

Do not argue about the placement. Measure it.

1. Delete the method from the candidate mixin.
2. Run the suite of the component that applies the fewest mixins.
3. A type error on a missing owner method proves that the placement is too high.
4. Restore the method.

The run costs less than a minute and it replaces a long discussion.

## The property round trip

A child element sometimes declares a property that the host forwards to it. The child then
passes the same value back to the host inside a question, such as a test for a selected item.

Two signs confirm the smell. The child declares the property with no observer, so a forward
never triggers a render. The only use of the value is an argument to a method on the owner.

Remove the property from the child. Let the child call the owner without it. Remove the forward
from every host and from the type definition of the child.

## What does not move

Keep a guard that encodes a real semantic difference. A check that selects between identity and
an identifier is a decision, not duplication. Move the comparison and keep the guard.

## Check a mixin before you adopt it

A missing dependency has an obvious fix: apply the mixin that declares the property. Read that
mixin first. A deprecated mixin adds one more caller to work that a later version removes.
State the deprecation and let the maintainer choose.
