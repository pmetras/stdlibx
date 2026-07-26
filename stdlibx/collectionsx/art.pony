use "../assertx"


class ArtTree[V: Any ref]
  """
  Adaptive Radix Tree (ART) — a space-efficient trie for `USize` keys.

  Based on Leis et al. ["The Adaptive Radix Tree: ARTful Indexing for
  Main-Memory Databases"](https://arxiv.org/pdf/1603.06549) (ICDE 2013).

  Keys are `USize` values decomposed byte-by-byte (most significant first) to
  create a trie of depth up to 8 on 64-bit systems. The tree uses 4 adaptive
  node types (`Node4`, `Node16`, `Node48`, `Node256`) that grow/shrink based on the
  number of children, optimizing memory usage. In this implementation, all node
  types are represented by a single class `_ArtNode[V]`.

  Features:
  - O(k) lookup, insert, delete where k ≤ 8 (key length in bytes)
  - Path compression: collapses single-child chains
  - Lazy leaf expansion: stores values directly when possible
  - In-order iteration via `keys()`
  """

  var _root: (_ArtNode[V] | None)
    """
    The root of the trie.
    """

  var _size: USize
    """
    The number of elements in the ART trie.
    """

  new create() =>
    """
    Create a new empty ART data structure.
    """
    _root = None
    _size = 0


  fun contains_key(key: USize): Bool =>
    """
    Returns true if the key exists in the tree.
    """
    match get(key)
    | None => false
    else
      true
    end


  fun size(): USize =>
    """
    Returns the number of entries in the ART data structure.
    """
    _size


  fun is_empty(): Bool =>
    """
    Return `true` when the ART data structure is empty.
    """
    _size == 0


  fun ref clear() =>
    """
    Remove all entries from the ART tree.
    """
    _root = None
    _size = 0


  fun get(key: USize): (this->V | None) =>
    """
    Look up the value associated with `key`. Returns `None` if not found.
    """
    try
      _lookup(_root, key, 0)?
    else
      None
    end


  fun _lookup(node: (this->_ArtNode[V] | None), key: USize, depth: USize)
    : this->V ? =>
    """
    Search recursively the content of the ART trie to find the element
    with key `key`.
    The search progresses deep into the trie using progressive bytes from the `key`
    until it reaches a value node.
    """
    match node
    | let n: this->_ArtNode[V] =>
      // Check prefix
      let prefix_len = n.prefix_len
      if prefix_len > 0 then
        var i: USize = 0
        while i < prefix_len do
          if _key_byte(key, depth + i) != n.prefix(i)? then
            error
          end
          i = i + 1
        end
      end

      let new_depth = depth + prefix_len
      if new_depth >= _key_len() then
        if n.has_value() then
          return n.get_value()?
        end
        error
      end

      let byte = _key_byte(key, new_depth)
      match n.find_child(byte)
      | let child: this->_ArtNode[V] =>
        _lookup(child, key, new_depth + 1)?
      else
        if n.has_value() and (n.num_children == 0) then
          return n.get_value()?
        end
        error
      end
    else
      error
    end


  fun ref insert(key: USize, value: V): V! =>
    """
    Insert `key` with `value`. Replaces existing value if key already exists.
    Returns the inserted value, allowing reuse. When the same key is inserted
    multiple times, the value gets overwritten with the latest value, but the
    key remains unique in the tree and it does not increase the elements count.
    """
    (let new_root, let replaced) = _insert(_root, key, value, 0)
    _root = new_root
    if not replaced then
      _size = _size + 1
    end
    consume value


  fun ref update(key: USize, value: V): (V^ | None) =>
    """
    Update the value associated with `key`. Returns the previous value if the
    key already existed, or None if this is a new key. This method is useful
    when you need to know what the previous value was, if any.
    """
    let old_value = get(key)
    insert(key, value)
    old_value


  fun ref insert_if_absent(key: USize, value: V): V! =>
    """
    Insert `key` with `value` only if the key doesn't already exist in the tree.
    Returns the inserted value if the key was new, or the existing value if the
    key already existed. This is useful for the common pattern:
    
    ```pony
    if not my_tree.contains(my_key) then
      my_tree(my_key) = my_value
    end
    ```
    
    This method can be used as a drop-in replacement for `insert` in such cases.
    """
    // First check if key exists without consuming the value
    try
      let existing = _lookup(_root, key, 0)?
      // Key already exists, return existing value
      consume existing
    else
      // Key doesn't exist, insert new value
      insert(key, value)
      consume value
    end


  fun ref _insert(node: (_ArtNode[V] | None), key: USize, value: V, depth: USize)
    : (_ArtNode[V], Bool) =>
    """
    Do the real job of inserting the `value` in the ART trie with `key` value.
    Radix trees have the useful property that each inner node represents a key
    prefix. Therefore, the keys are implicitly stored in the tree structure,
    and can be reconstructed from the paths to the leaf nodes. This saves space,
    because the keys do not have to be stored explicitly. Nevertheless, even
    with this implicit prefix compression of keys and the use of adaptive nodes,
    there are cases, in particular with long keys, where the space consumption
    per key is large. We therefore use two additional, well-known techniques that
    allow to decrease the height by reducing the number of nodes. These techniques
    are very effective for long keys, increasing performance significantly for
    such indexes. Equally important is that they reduce space consumption, and
    ensure a small worst-case space bound.

    With the first technique, lazy expansion, inner nodes are only created if
    they are required to distinguish at least two leaf nodes.

    Path compression, the second technique, removes all inner nodes that have
    only a single child.

    Return a tuple with the created node and a boolean indicating if the
    value already existed or not.
    """
    match node
    | None =>
      // When the ART is empty, just create a new leaf node.
      let leaf = _ArtNode[V].create_leaf(key, value, depth)
      (leaf, false)
    | let n: _ArtNode[V] =>
      // Check prefix match
      let prefix_len = n.prefix_len
      var mismatch: USize = 0
      while mismatch < prefix_len do
        try
          if _key_byte(key, depth + mismatch) != n.prefix(mismatch)? then
            break
          end
        else
          break
        end
        mismatch = mismatch + 1
      end

      if mismatch < prefix_len then
        // Prefix mismatch: split
        let new_node = _ArtNode[V].create_inner()
        new_node.prefix.append(n.prefix, 0, mismatch)
        new_node.prefix_len = mismatch

        try
          let old_byte = n.prefix(mismatch)?
          let old_prefix = Array[U8](prefix_len - mismatch - 1)
          old_prefix.append(n.prefix, mismatch + 1, prefix_len - mismatch - 1)
          n.prefix.clear()
          n.prefix.append(old_prefix)
          n.prefix_len = prefix_len - mismatch - 1
          new_node.add_child(old_byte, n)
        end

        let new_depth = depth + mismatch
        let new_byte = _key_byte(key, new_depth)
        let leaf = _ArtNode[V].create_leaf(key, value, new_depth + 1)
        new_node.add_child(new_byte, leaf)

        return (new_node, false)
      end

      // Full prefix match
      let new_depth = depth + prefix_len
      // We've reached the length of the key
      if new_depth >= _key_len() then
        let was_set = n.has_value()
        n.set_value(value)
        n.stored_key = key
        return (n, was_set)
      end

      // We've not reached the length of the key yet, we can recurse
      let byte = _key_byte(key, new_depth)
      match n.find_child_ref(byte)
      | let child: _ArtNode[V] =>
        (let new_child, let replaced) = _insert(child, key, value, new_depth + 1)
        n.replace_child(byte, new_child)
        (n, replaced)
      else
        let leaf = _ArtNode[V].create_leaf(key, value, new_depth + 1)
        n.add_child(byte, leaf)
        (n, false)
      end
    end


  fun ref delete(key: USize) =>
    """
    Delete `key` from the tree.
    """
    (let new_root, let was_found) = _delete(_root, key, 0)
    _root = new_root
    if was_found then _size = _size - 1 end


  fun ref _delete(node: (_ArtNode[V] | None), key: USize, depth: USize)
    : ((_ArtNode[V] | None), Bool) =>
    """
    Do the real work of removing a value from the ART data structure.

    The implementation of deletion is symmetrical to insertion. The leaf
    is removed from an inner node, which is shrunk if necessary. If that
    node now has only one child, it is replaced by its child and the
    compressed path is adjusted.

    Return a tuple with the node and a boolean, `true` if the value
    existed in the trie.
    """
    match node
    | None => (None, false)
    | let n: _ArtNode[V] =>
      // Check if key prefix matches
      let prefix_len = n.prefix_len
      var i: USize = 0
      while i < prefix_len do
        try
          if _key_byte(key, depth + i) != n.prefix(i)? then
            return (n, false)
          end
        else
          return (n, false)
        end
        i = i + 1
      end

      // When we reach the length of the key prefix and we've found the key
      let new_depth = depth + prefix_len
      if new_depth >= _key_len() then
        let was_set = n.has_value()
        n.clear_value()
        if n.num_children == 0 then
          return (None, was_set)
        end
        return (n, was_set)
      end

      // We check if we find the key at an intermediate level of the key prefix
      let byte = _key_byte(key, new_depth)
      match n.find_child_ref(byte)
      | let child: _ArtNode[V] =>
        (let new_child, let was_found) = _delete(child, key, new_depth + 1)
        // Depending where we found the node
        if was_found then
          match new_child
          | let nc: _ArtNode[V] =>
            n.replace_child(byte, nc)
          | None =>
            n.remove_child(byte)
          end
          if (n.num_children == 1) and (not n.has_value()) then
            try
              (let only_byte, let only_child) = n.single_child()?
              let merged = Array[U8](n.prefix_len + 1 + only_child.prefix_len)
              merged.append(n.prefix)
              merged.push(only_byte)
              merged.append(only_child.prefix)
              only_child.prefix.clear()
              only_child.prefix.append(merged)
              only_child.prefix_len = merged.size()
              return (only_child, true)
            end
          end
          if (n.num_children == 0) and (not n.has_value()) then
            return (None, true)
          end
          (n, true)
        else
          (n, false)
        end
      else
        (n, false)
      end
    end


  fun keys(): ArtKeys[V] ref^ =>
    """
    Lazy forward iterator over all keys in ascending order.
    """
    ArtKeys[V]._create(_root)


  fun ref values(): ArtValues[V] ref^ =>
    """
    Lazy forward iterator over all values in ascending key order.
    """
    ArtValues[V]._create(_root)


  fun ref pairs(): ArtPairs[V] ref^ =>
    """
    Lazy forward iterator over all (key, value) pairs in ascending key order.
    """
    ArtPairs[V]._create(_root)


  fun rkeys(): ArtRKeys[V] ref^ =>
    """
    Lazy reverse iterator over all keys in descending order.
    """
    ArtRKeys[V]._create(_root)


  fun ref rvalues(): ArtRValues[V] ref^ =>
    """
    Lazy reverse iterator over all values in descending key order.
    """
    ArtRValues[V]._create(_root)


  fun ref rpairs(): ArtRPairs[V] ref^ =>
    """
    Lazy reverse iterator over all (key, value) pairs in descending key order.
    """
    ArtRPairs[V]._create(_root)


  fun tag _key_byte(key: USize, depth: USize): U8 =>
    """
    Extract byte at position `depth` from the key (MSB first).

    *CAUTION*: The key must be big endian.
    """
    let shift = ((_key_len() - 1) - depth) * 8
    (key >> shift).u8()


  fun tag _key_len(): USize =>
    """
    Number of bytes in a USize key.
    """
    USize(0).bytewidth()


class _ArtNode[V: Any ref]
  """
  Unified ART node. Uses parallel arrays for keys and children.
  Adapts from small (4) to large (256) as needed. In the [original
  research paper](https://db.in.tum.de/~leis/papers/ART.pdf), there were
  4 types of nodes that would be named `_ArtNode4`, `_ArtNode16`,
  `_ArtNode48` and `_ArtNode256`.

  For simplicity, this implementation uses a sorted keys array with linear
  search for small nodes and a 256-slot direct array for large nodes (>48
  children). The node type is determined by `num_children`:
  - 0-4 ==> `_ArtNode4`: small linear scan
  - 5-16 ==> `_ArtNode16`: sorted keys, linear/binary search
  - 17-48 ==> `_ArtNode48`: index array (256-byte) + children array
  - 49-256 ==> `_ArtNode256`: direct 256-slot array
  """

  embed prefix: Array[U8]
    """
    Path compression: common prefix bytes.
    """

  var prefix_len: USize
    """
    The length of the prefix (number of bytes).
    """

  embed _value: Array[V]
    """
    Value stored at this node. 0 elements = no value, 1 element = has value.
    """

  var stored_key: USize
    """
    Full key for value reconstruction during iteration.
    """

  var num_children: USize
    """
    The number of children nodes of the node.
    """

  // Storage for children. We use a simple sorted (key, child) pairs approach
  // for all node sizes. For Node256 we use a 256-slot direct array.
  var _keys: Array[U8]
    """
    The byte part of the prefix used to access a child node, stored in an
    array.
    """

  var _children: Array[_ArtNode[V]]
    """
    The array of the children nodes, used when the node is not an `_ArtNode256`.
    """

  var _direct: (Array[(_ArtNode[V] | None)] | None)
    """
    256-slot direct array used when num_children > 48.
    """

  new create_leaf(key: USize, value: V, depth: USize) =>
    """
    Create and initialize a leaf node for `key` and `value`,
    at `depth` bytes of prefix.
    """
    // Initialize the leaf
    prefix = Array[U8]
    prefix_len = 0
    _value = Array[V](1)
    _value.push(value)
    stored_key = key
    num_children = 0
    _keys = Array[U8]
    _children = Array[_ArtNode[V]]
    _direct = None

    // Store remaining key bytes as prefix
    let key_len: USize = ArtTree[V]._key_len()
    var d = depth
    while d < key_len do
      let shift = ((key_len - 1) - d) * 8
      prefix.push((key >> shift).u8())
      d = d + 1
    end
    prefix_len = prefix.size()


  new create_inner() =>
    """
    Create an empty generic inner node.
    """
    prefix = Array[U8]
    prefix_len = 0
    _value = Array[V]
    stored_key = 0
    num_children = 0
    _keys = Array[U8]
    _children = Array[_ArtNode[V]]
    _direct = None


  fun has_value(): Bool =>
    """
    Check if a node contains a value.
    """
    _value.size() > 0


  fun get_value(): this->V ? =>
    """
    Get the value stored on the node.
    """
    _value(0)?


  fun ref set_value(value: V) =>
    """
    Set the value on the node.
    """
    _value.clear()
    _value.push(value)


  fun ref clear_value() =>
    """
    Remove the value from the node.
    """
    _value.clear()


  fun find_child(byte: U8): (this->_ArtNode[V] | None) =>
    """
    Find the child associated with the `byte` key.
    """
    match _direct
    | let d: this->Array[(_ArtNode[V] | None)] =>
      // `_ArtNode256` uses direct access
      try
        return d(byte.usize())?
      end
    else
      // Linear scan of the byte keys to find the searched byte.
      var i: USize = 0
      while i < _keys.size() do
        try
          if _keys(i)? == byte then
            return _children(i)?
          end
        end
        i = i + 1
      end
      None
    end


  fun ref find_child_ref(byte: U8): (_ArtNode[V] | None) =>
    """
    Find the child associated with the `byte` key.
    """
    match _direct
    | let d: Array[(_ArtNode[V] | None)] =>
      // `_ArtNode256` uses direct access
      try
        d(byte.usize())?
      end
    else
      // Linear scan of the byte keys to find the searched byte.
      var i: USize = 0
      while i < _keys.size() do
        try
          if _keys(i)? == byte then
            return _children(i)?
          end
        end
        i = i + 1
      end
      None
    end


  fun ref add_child(byte: U8, child: _ArtNode[V]) =>
    """
    Add a child node under the key `byte`.
    """
    match _direct
    | let d: Array[(_ArtNode[V] | None)] =>
      // `_ArtNode256` with direct access
      try
        d(byte.usize())? = child
      end
      num_children = num_children + 1
    else
      // Check if we need to upgrade to direct array
      if num_children >= 48 then
        _upgrade_to_direct()
        match _direct
        | let d: Array[(_ArtNode[V] | None)] =>
          try
            d(byte.usize())? = child
          end
          num_children = num_children + 1
        end
        return
      end

      // Insert in sorted position for all other types of `_ArtNodeX`
      var pos: USize = 0
      while pos < _keys.size() do
        try
          if _keys(pos)? > byte then
            break
          end
        end
        pos = pos + 1
      end
      try
        _keys.insert(pos, byte)?
        _children.insert(pos, child)?
      end
      num_children = num_children + 1
    end


  fun ref replace_child(byte: U8, child: _ArtNode[V]) =>
    """
    Replace a child node à position `byte` of the prefix key.
    """
    match _direct
    | let d: Array[(_ArtNode[V] | None)] =>
      // Direct access with `_ArtNode256`
      try
        d(byte.usize())? = child
      end
    else
      // Sequential access for other `_ArtNodeX` types.
      var i: USize = 0
      while i < _keys.size() do
        try
          if _keys(i)? == byte then
            _children(i)? = child
            return
          end
        end
        i = i + 1
      end
    end


  fun ref remove_child(byte: U8) =>
    """
    Remove the child node à position `byte` in the prefix.
    """
    match _direct
    | let d: Array[(_ArtNode[V] | None)] =>
      // `_ArtNode256` with direct access to children.
      try d(byte.usize())? = None end
      num_children = num_children - 1
      // Downgrade if needed
      if num_children <= 48 then
        _downgrade_from_direct()
      end
    else
      // Sequential access in the `_keys` to find the byte.
      var i: USize = 0
      while i < _keys.size() do
        try
          if _keys(i)? == byte then
            _keys.delete(i)?
            _children.delete(i)?
            num_children = num_children - 1
            return
          end
        end
        i = i + 1
      end
    end


  fun single_child(): (U8, this->_ArtNode[V]) ? =>
    """
    Returns the single child's byte and node. Errors if not exactly one child.
    """
    if num_children != 1 then
      error
    end

    match _direct
    | let d: this->Array[(_ArtNode[V] | None)] =>
      // With `_ArtNode256` and direct storage, we don't know which `byte` key
      // as been used for storage and we must loop to find the index.
      var i: USize = 0
      while i < 256 do
        match try d(i)? end
        | let c: this->_ArtNode[V] => return (i.u8(), c)
        end
        i = i + 1
      end
      // We haven't found a node in the `_direct` array.
      error
    else
      (_keys(0)?, _children(0)?)
    end


  fun _child_at(idx: USize): this->_ArtNode[V] ? =>
    """
    Return the `idx`-th child in byte-sorted order.
    """
    match _direct
    | let d: this->Array[(_ArtNode[V] | None)] =>
      // Scan the 256-slot direct array for the idx-th non-None entry
      var count: USize = 0
      var i: USize = 0
      while i < 256 do
        match try d(i)? end
        | let c: this->_ArtNode[V] =>
          if count == idx then return c end
          count = count + 1
        end
        i = i + 1
      end
      error
    else
      _children(idx)?
    end


  fun _children_in_order(): Array[this->_ArtNode[V]] =>
    """
    Return children in byte-sorted order for in-order iteration.
    """
    let result = Array[this->_ArtNode[V]](num_children)
    match _direct
    | let d: this->Array[(_ArtNode[V] | None)] =>
      // Direct access of `_ArtNode256` children
      var i: USize = 0
      while i < 256 do
        match try d(i)? end
        | let c: this->_ArtNode[V] => result.push(c)
        end
        i = i + 1
      end
    else
      result.append(_children)
    end
    result


  fun ref _upgrade_to_direct() =>
    """
    Upgrade a `_ArtNode48` to a `_ArtNode256` node with children nodes
    direct storage, instead of byte indirection.
    """
    // Create the resulting `_ArtNode256`
    let d = Array[(_ArtNode[V] | None)].init(None, 256)
    // Transfer all values to direct access indexed by byte key.
    var i: USize = 0
    while i < _keys.size() do
      try
        let byte = _keys(i)?
        d(byte.usize())? = _children(i)?
      end
      i = i + 1
    end
    _direct = d
    // And then clear indirect access arrays
    _keys.clear()
    _children.clear()


  fun ref _downgrade_from_direct() =>
    """
    Downgrade a `_ArtNode256` to a `_ArtNode48` node with byte key indirect
    access to values.
    """
    match _direct
    | let d: Array[(_ArtNode[V] | None)] =>
      let new_keys = Array[U8](num_children)
      let new_children = Array[_ArtNode[V]](num_children)
      var i: USize = 0
      while i < 256 do
        match try d(i)? end
        | let c: _ArtNode[V] =>
          new_keys.push(i.u8())
          new_children.push(c)
        end
        i = i + 1
      end
      _keys = new_keys
      _children = new_children
      _direct = None
    end


class _ArtForwardWalker[V: Any ref]
  """
  Stack-based forward (ascending key order) DFS walker over ART nodes.

  Maintains the invariant that after `_advance()`, either the stack is empty
  or the top entry is a node whose value has not yet been yielded.

  The stack stores `(node, child_index, value_done)` triples where
  `child_index` is the next child to descend into and `value_done` indicates
  whether the node's own value has already been returned.
  """

  var _root: (_ArtNode[V] | None)
    """
    The root node of the ART tree.
    """

  embed _stack: Array[(_ArtNode[V], USize, Bool)]
    """
    The stack used to traverse the ART tree.
    """

  new create(root: (_ArtNode[V] | None)) =>
    """
    Create a new forward ART walker.
    """
    _root = root
    _stack = Array[(_ArtNode[V], USize, Bool)]
    match root
    | let r: _ArtNode[V] => _stack.push((r, 0, false))
    end
    _advance()


  fun ref has_next(): Bool =>
    """
    Is there another value available in the ART tree?
    """
    _stack.size() > 0


  fun ref next_node(): _ArtNode[V] ? =>
    """
    Pop the current value-bearing node and advance to the next one.
    """
    (let node, let child_index, _) = _stack.pop()?
    // Push back with value_done=true so _advance processes children
    _stack.push((node, child_index, true))
    _advance()
    node


  fun ref rewind() =>
    """
    Reset the walker to the beginning.
    """
    _stack.clear()
    match _root
    | let r: _ArtNode[V] => _stack.push((r, 0, false))
    end
    _advance()


  fun ref _advance() =>
    """
    Advance until the top of stack is a value-bearing node with
    `value_done == false`, or the stack is empty.

    Forward pre-order: yield value first, then visit children left-to-right.
    """
    while _stack.size() > 0 do
      try
        (let node, let child_index, let value_done) = _stack.pop()?
        if (not value_done) and node.has_value() then
          // Found the next value to yield
          _stack.push((node, child_index, false))
          return
        end
        if child_index < node.num_children then
          // Push parent back for remaining children
          _stack.push((node, child_index + 1, true))
          // Push child for processing
          let child = node._child_at(child_index)?
          _stack.push((child, 0, false))
        end
        // else: node fully processed, loop pops the parent
      else
        return
      end
    end


class _ArtReverseWalker[V: Any ref]
  """
  Stack-based reverse (descending key order) DFS walker over ART nodes.

  Maintains the invariant that after `_advance()`, either the stack is empty
  or the top entry is a node whose value has not yet been yielded.

  The stack stores `(node, remaining)` pairs where `remaining` is the number
  of children still to descend into from the right.
  """
  var _root: (_ArtNode[V] | None)
    """
    The root of the ART trie.
    """

  embed _stack: Array[(_ArtNode[V], USize)]
    """
    The stack used to push up the levels of the ART trie.
    """

  new create(root: (_ArtNode[V] | None)) =>
    """
    Create and initialize the reverse walker with the root of the ART trie.
    """
    _root = root
    _stack = Array[(_ArtNode[V], USize)]
    match root
    | let r: _ArtNode[V] => _stack.push((r, r.num_children))
    end
    _advance()


  fun ref has_next(): Bool =>
    """
    Is there another entry available in the ART data structure?
    """
    _stack.size() > 0


  fun ref next_node(): _ArtNode[V] ? =>
    """
    Pop the current value-bearing node and advance to the next one.
    """
    (let node, _) = _stack.pop()?
    _advance()
    node


  fun ref rewind() =>
    """
    Reset the walker to the beginning.
    """
    _stack.clear()
    match _root
    | let r: _ArtNode[V] => _stack.push((r, r.num_children))
    end
    _advance()


  fun ref _advance() =>
    """
    Advance until the top of stack is a value-bearing node with all its
    children already processed, or the stack is empty.

    Reverse post-order: visit children right-to-left, then yield value.
    """
    while _stack.size() > 0 do
      try
        (let node, let remaining) = _stack.pop()?
        if remaining > 0 then
          // Still have children to process (right-to-left)
          _stack.push((node, remaining - 1))
          let child = node._child_at(remaining - 1)?
          _stack.push((child, child.num_children))
        elseif node.has_value() then
          // All children done, this node has a value to yield
          _stack.push((node, 0))
          return
        end
        // else: no children left and no value — skip
      else
        return
      end
    end


class ArtKeys[V: Any ref] is Iterator[USize]
  """
  Lazy forward iterator over keys in an ART tree, in ascending order.

  Uses `box` access to nodes so that `keys()` can be called on both
  `ref` and `box` tree references (keys are `USize val`).
  """

  var _root: (_ArtNode[V] box | None)
    """
    The root node of the ART data structure.
    """

  embed _stack: Array[(_ArtNode[V] box, USize, Bool)]
    """
    The stack used to traverse the ART trie.
    """

  new _create(root: (_ArtNode[V] box | None)) =>
    """
    Create and initialize a new ART keys iterator.
    """
    _root = root
    _stack = Array[(_ArtNode[V] box, USize, Bool)]
    match root
    | let r: _ArtNode[V] box => _stack.push((r, 0, false))
    end
    _advance()


  fun ref has_next(): Bool =>
    """
    Are there keys remaining?
    """
    _stack.size() > 0


  fun ref next(): USize ? =>
    """
    Return the next ART key in the ART trie.
    """
    (let node, let ci, _) = _stack.pop()?
    _stack.push((node, ci, true))
    _advance()
    node.stored_key


  fun ref rewind() =>
    """
    Rewind this iterator back to the first key.
    """
    _stack.clear()
    match _root
    | let r: _ArtNode[V] box => _stack.push((r, 0, false))
    end
    _advance()


  fun ref _advance() =>
    """
    Advance to the next key.
    """
    while _stack.size() > 0 do
      try
        (let node, let ci, let vd) = _stack.pop()?
        if (not vd) and node.has_value() then
          _stack.push((node, ci, false))
          return
        end
        if ci < node.num_children then
          _stack.push((node, ci + 1, true))
          let child = node._child_at(ci)?
          _stack.push((child, 0, false))
        end
      else
        return
      end
    end


class ArtValues[V: Any ref] is Iterator[V]
  """
  Lazy forward iterator over values in an ART tree, in ascending key order.
  """

  embed _walker: _ArtForwardWalker[V]
    """
    The forward walker to traverse the ART trie.
    """

  new _create(root: (_ArtNode[V] | None)) =>
    """
    Create the walker over the values.
    """
    _walker = _ArtForwardWalker[V](root)


  fun ref has_next(): Bool =>
    """
    Are there remaining values in the iterator?
    """
    _walker.has_next()


  fun ref next(): V ? =>
    """
    Get the next value if it exists.
    """
    _walker.next_node()?.get_value()?


  fun ref rewind() =>
    """
    Rewind this iterator back to the first value.
    """
    _walker.rewind()


class ArtPairs[V: Any ref] is Iterator[(USize, V)]
  """
  Lazy forward iterator over `(key, value)` pairs in an ART tree,
  in ascending key order.
  """

  embed _walker: _ArtForwardWalker[V]
    """
    The walker used to traverse the ART trie.
    """

  new _create(root: (_ArtNode[V] | None)) =>
    """
    Create the iterator to traverse the ART trie.
    """
    _walker = _ArtForwardWalker[V](root)


  fun ref has_next(): Bool =>
    """
    Is there a remaining entry in the ART trie?
    """
    _walker.has_next()


  fun ref next(): (USize, V) ? =>
    """
    Get the next ART entry if it exists.
    """
    let n = _walker.next_node()?
    (n.stored_key, n.get_value()?)


  fun ref rewind() =>
    """
    Rewind this iterator back to the first pair.
    """
    _walker.rewind()


class ArtRKeys[V: Any ref] is Iterator[USize]
  """
  Lazy reverse iterator over keys in an ART tree, in descending order.

  Uses `box` access to nodes so that `rkeys()` can be called on both
  `ref` and `box` tree references (keys are `USize val`).
  """

  var _root: (_ArtNode[V] box | None)
    """
    The root of the ART trie.
    """

  embed _stack: Array[(_ArtNode[V] box, USize)]
    """
    The stack used to traverse the ART trie.
    """

  new _create(root: (_ArtNode[V] box | None)) =>
    """
    Create and initialize the iterator.
    """
    _root = root
    _stack = Array[(_ArtNode[V] box, USize)]
    match root
    | let r: _ArtNode[V] box => _stack.push((r, r.num_children))
    end
    _advance()


  fun ref has_next(): Bool =>
    """
    Is there a previous key in the ART trie?
    """
    _stack.size() > 0


  fun ref next(): USize ? =>
    """
    Get the previous key if it exists.
    """
    (let node, _) = _stack.pop()?
    _advance()
    node.stored_key


  fun ref rewind() =>
    """
    Rewind this iterator back to the last key (highest).
    """
    _stack.clear()
    match _root
    | let r: _ArtNode[V] box => _stack.push((r, r.num_children))
    end
    _advance()


  fun ref _advance() =>
    """
    Move the current cursor on the iterator.
    """
    while _stack.size() > 0 do
      try
        (let node, let remaining) = _stack.pop()?
        if remaining > 0 then
          _stack.push((node, remaining - 1))
          let child = node._child_at(remaining - 1)?
          _stack.push((child, child.num_children))
        elseif node.has_value() then
          _stack.push((node, 0))
          return
        end
      else
        return
      end
    end


class ArtRValues[V: Any ref] is Iterator[V]
  """
  Lazy reverse iterator over values in an ART tree, in descending
  key order.
  """

  embed _walker: _ArtReverseWalker[V]
    """
    The walker used to travers the ART trie in descending
    order of key value.
    """

  new _create(root: (_ArtNode[V] | None)) =>
    """
    Create the new iterator.
    """
    _walker = _ArtReverseWalker[V](root)


  fun ref has_next(): Bool =>
    """
    Is there a previous value in the ART trie?
    """
    _walker.has_next()


  fun ref next(): V ? =>
    """
    Get the previous value if it exists.
    """
    _walker.next_node()?.get_value()?


  fun ref rewind() =>
    """
    Rewind this iterator back to the last value (highest key).
    """
    _walker.rewind()


class ArtRPairs[V: Any ref] is Iterator[(USize, V)]
  """
  Lazy reverse iterator over `(key, value)` pairs in an ART tree,
  in descending key order.
  """

  embed _walker: _ArtReverseWalker[V]
    """
    The walker used to traverse the ART trie in reverse
    key order.
    """

  new _create(root: (_ArtNode[V] | None)) =>
    """
    Create and initalize the reverse key iterator.
    """
    _walker = _ArtReverseWalker[V](root)


  fun ref has_next(): Bool =>
    """
    Is the another ART entry by key descending value?
    """
    _walker.has_next()


  fun ref next(): (USize, V) ? =>
    """
    Get the previous pair of key, value from the ART trie
    by descending key value.
    """
    let n = _walker.next_node()?
    (n.stored_key, n.get_value()?)


  fun ref rewind() =>
    """
    Rewind this iterator back to the last pair (highest key).
    """
    _walker.rewind()
