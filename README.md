# SoftTree

SoftTree is a library designed to help you automate the execution of complex dependencies. The name is a blend of **Software** and **Tree**, developed to simplify the implementation of structural dependencies and data dynamics within software.

Currently, the **Lua** version is under active maintenance, with plans to release **C** and **Rust** versions in the future.

---

## Design Principles

SoftTree is structured as a **Directed Acyclic Graph (DAG)** with the following characteristics:

- **Root Node:** A unique root exists that can reach any node, while no node can reach the root.
- **Flexible Hierarchy:** Unlike traditional trees, SoftTree allows a single node to have multiple parents.
- **Relationship Constraints:**
  - **Read-only Access:** Parents are `readonly` from the perspective of their child nodes.
  - **Top-down Isolation:** Parents cannot "see" their child nodes.
  - **Indirect Influence:** Children cannot modify parents directly; they must use functions to influence them indirectly.
  - **External Isolation:** Nodes should have no contact with each other outside the tree structure.
  - **Tag-based Referencing:** Nodes reference each other via `tags`. If a tag is not manually set, one will be generated automatically.

---

## Core Components

### 1. Node

#### Attributes

- `String[] parentTags`: An array of tags identifying parent nodes.
- `bool ready`: Indicates the state between `load` and `unload`.
- `bool dirty`: Data "dirty" flag; propagates downward automatically.
- `ptr entity`: Managed externally (it is recommended that the `node.entity` address remains constant).

#### Methods

- `func load`: Initialization function.
- `func unload`: De-initialization function.
- `func update`: Called automatically when `dirty` is true; resets `dirty` to false upon completion.

> **Note:** A child node's update may cause a parent node to become dirty. This is handled via a buffering mechanism and processed during the next `tree.update`. While infinite loops are possible, they are not treated as internal library errors.

---

### 2. Tree

#### Attributes

- `KeyValue nodeDict`: The primary storage for nodes, mapped as `nodeDict[tag] = node`.
- `Node[] nodeArray`: A sorted array of nodes generated after `load`, ensuring parents appear before children.
- `bool dirty`: Structural dirty flag (triggers topological re-indexing).
- `bool ready`: Indicates the state between `load` and `unload`.
- `Node root`: The root node; its content is entirely automated and requires no manual management.
- `Buffer buffer`: (TODO) Manages pending changes within the tree.

#### Methods

- `func load(tree)`: Optimizes the `nodeArray` index and calls `node.load` for all nodes.
- `func unload(tree)`: Iterates through and calls `node.unload` for all nodes.
- `func update(tree)`: Processes the buffer, updates the tree structure if `tree.dirty` is true (e.g., re-sorting `nodeArray`), and iterates through nodes to call `node.update` where `node.dirty` is true.
- `func insert(tree, node, tag)`: Inserts a node and sets `tree.dirty = true`.
- `func remove(tree, node)`: Fails if the node has children; otherwise removes it and sets `tree.dirty = true`.
- `func getTagged(tree, tag)`: Retrieves a node by its tag.

---

## Roadmap

- [x] Lua Version (Maintained)
- [ ] C Version (Planned)
- [ ] Rust Version (Planned)
