# Agents Overview — Swift Home Automation Package

This repository implements a **Swift Package** for controlling a DeltaDore box using a functional programming architecture and strong testability guarantees.  
Agents working with this repo (AI assistants, automation tools, or new team members) should understand:

- Functional design principles (immutability, pure functions, higher order functions, side effects, composition)
- How we structure side effects via dependency injection
- SOLID principles applied in a Swift + functional programming context
- Testability via injecting functions and capabilities
- Our Git workflow (linear history, feature branches, fast-forward merges)

> This high-level overview provides context. Read the doc and find detailed procedural steps and examples through dedicated **Agent Skills** in `skills/`.

---

## Plan

For long reasoning operations and complex tasks we do an execution plan upfront and ask for validation.
When executing the plan, you can use parallel tasks/sub-agents to optimize the execution and ask sub-agents to challenge themselves and the main agent.

---

## Functional Architecture Philosophy

**North Star**  
We partition code into:

1. **Inert Domain** — immutable data (`struct`/`enum`), no side effects  
2. **Pure Computations** — deterministic pure functions (input → output)  
3. **Actions/Effects** — side effects (network, hardware, IO) at the edges

**Key Concepts**  
- Immutability by default  
- Pure functions everywhere possible  
- Composition over inheritance  
- Higher-order functions and partial application (or curry when this apply)
- Lazy/thunked dependencies for expensive resources

We apply SOLID in a Swift FP context:

- **S**ingle Responsibility: small functions that performs one thing, narrow types
- **O**pen/Closed: extend via composition, not inheritance (when possible)
- **L**iskov: injected functions uphold contracts
- **I**nterface Segregation: tiny capability structs or functions, not fat protocols
- **D**ependency Inversion: domain depends on capabilities, not implementations

These emphasize modularity without unnecessary abstractions.

This aligns with modern functional design patterns that emphasize clarity, testability, and correctness.

- Use Enums as a namespace for related free functions.
- A function should be max 30 lines of code, split it otherwise (use composition).
- A file should be max 300 lines of code, split it otherwise (use composition and extensions).
- When working in a swift package, types visibility is important, by default types should not be visible from the outside (internal), a type should be public only if it is part of the public API used by the end client.

---

## Testability Patterns

We favor **function injection instead of object mocking**:

- Capability structs of closures (e.g., network client, clock, logger)
- Use of higher order function
- Inject only what a unit needs (small slices)
- Pure core logic that can be tested with no environment dependencies
- We focus on unit tests (not integration tests).
- Always use the Swift Testing framework and use the Given, When, Then pattern

---

## Git Workflow Summary

We use the Git CLI.

We adopt a **GitHub Flow** style:

- One long-lived `main` branch
- Short-lived feature/fix branches
- Frequent rebasing from `main`
- Fast-forward merges only
- Destructive operations are forbidden unless explicit (reset --hard, clean, restore, rm, …)

This yields a clean, linear history and makes `git bisect` and blame more effective.

--

## How to run and test

In the context of a Swift package, we use the Swift CLI with commands like `swift build` or `swift test`
If this is a full Xcode project, we can use the XCodeBuildMCP server.

--

## Swift documentation

When needed use the Cupertino MCP server to access the officiel Swift documentation and Apple coding guides.

--

## Docs index

Add new documentation references here going forward.

- `docs/sqlite-persistence.md` — SQLite persistence overview, usage, and extension notes
- `docs/tydom-connection.md` — TydomConnection execution plan, behavior, and usage
- `docs/tydom-commands.md` — TydomCommand mechanism, legacy factory list, and usage
- `docs/tydom-decoding.md` — Message decoding pipeline, cache dependencies, and usage
