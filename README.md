# SoftTree

SoftTree is a library designed to manage complex dependency relationships, facilitating the efficient implementation of software structural dependencies and dynamic data flows.

## Features

* **DAG Structure**: Based on Directed Acyclic Graphs (DAG), supporting multiple parent node references.
* **Unidirectional Visibility**: Child nodes have read-only access to parent nodes; parent nodes cannot see child nodes.
* **Decoupled Design**: Nodes are referenced via `Tags`, prohibiting direct connections outside the tree structure.
* **Automated State Management**: Supports data dirty-checking and automatic downward propagation.

## Design Specifications

### 1. Node

A Node is the execution unit, containing state information and lifecycle callbacks.

| Property | Type | Description |
| --- | --- | --- |
| `parentTags` | `String[]` | Array of parent node tags |
| `ready` | `bool` | Initialization status (post-load, pre-unload) |
| `dirty` | `bool` | Data dirty flag; propagates automatically to children |
| `entity` | `ptr` | Pointer to an externally managed entity |

**Core Methods:**

* `load()`: Initialization; called exactly once.
* `unload()`: De-initialization.
* `update()`: Triggered when `dirty` is `true`; resets to `false` after execution.
* `run()`: Continuous polling/execution.

### 2. Tree

The Tree is responsible for topological sorting and lifecycle scheduling of nodes.

| Property | Description |
| --- | --- |
| `nodeDict` | Dictionary storing nodes, indexed by `Tag` |
| `nodeArray` | Topologically sorted array (parents before children) |
| `dirty` | Structural dirty flag; indicates changes in tree topology |
| `root` | Automatically managed virtual root node |

**Core Methods:**

* `insert(node, tag)`: Inserts a node and sets the structural `dirty` flag to `true`.
* `remove(node)`: Removes a leaf node (fails if the node has children).
* `update()`: Re-sorts `nodeArray` if the tree is structurally dirty, then traverses nodes to handle their respective `update` calls.
* `run()`: Traverses and executes the `run` method for all nodes in order.

## Roadmap

* [x] **Lua**: Actively maintained
* [ ] **C**: Planned
* [ ] **Rust**: Planned

---

*Note: Child nodes triggering a "dirty" state in parent nodes may cause infinite loops. Logical integrity must be maintained by the implementing business logic.*