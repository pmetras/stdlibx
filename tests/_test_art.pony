// Tests for ArtTree (Adaptive Radix Tree).

use "../stdlibx/pony_testx"
use "collections"

use "../stdlibx/collectionsx"


primitive ArtTreeTests
  """
  Tests for ArtTree adaptive radix tree.
  """
  fun tests(test: PonyTest) =>
    test(_TestArtBasicInsertGet)
    test(_TestArtDelete)
    test(_TestArtKeys)
    test(_TestArtNodeGrowth)
    test(_TestArtPathCompression)
    test(_TestArtOverwrite)
    test(_TestArtClear)
    test(_TestArtDuplicateInsert)
    test(_TestArtCollectionsAPI)
    test(_TestArtReverseIterators)
    test(_TestArtIteratorRewind)


class _TestVal
  """Simple ref class for testing ART with ref values."""
  let v: USize
  new create(v': USize) => v = v'


class iso _TestArtBasicInsertGet is UnitTest
  """
  Test basic insert and get operations.
  """
  fun name(): String => "art/Basic insert and get"

  fun apply(h: TestHelper) =>
    let tree = ArtTree[_TestVal]
    h.assert_true(tree.is_empty())
    h.assert_true(tree.size() == 0)

    tree.insert(42, _TestVal(100))
    h.assert_false(tree.is_empty())
    h.assert_true(tree.size() == 1)

    match tree.get(42)
    | let tv: _TestVal box => h.assert_true(tv.v == 100)
    else h.fail("expected value for key 42")
    end

    h.assert_true(tree.get(43) is None)

    // Insert multiple keys
    tree.insert(10, _TestVal(10))
    tree.insert(1000, _TestVal(1000))
    tree.insert(0, _TestVal(0))
    h.assert_true(tree.size() == 4)

    match tree.get(0)
    | let tv: _TestVal box => h.assert_true(tv.v == 0)
    else h.fail("expected value for key 0")
    end

    match tree.get(1000)
    | let tv: _TestVal box => h.assert_true(tv.v == 1000)
    else h.fail("expected value for key 1000")
    end


class iso _TestArtDelete is UnitTest
  """
  Test delete operations.
  """
  fun name(): String => "art/Delete"

  fun apply(h: TestHelper) =>
    let tree = ArtTree[_TestVal]
    tree.insert(1, _TestVal(1))
    tree.insert(2, _TestVal(2))
    tree.insert(3, _TestVal(3))
    h.assert_true(tree.size() == 3)

    tree.delete(2)
    h.assert_true(tree.size() == 2)
    h.assert_true(tree.get(2) is None)

    match tree.get(1)
    | let tv: _TestVal box => h.assert_true(tv.v == 1)
    else h.fail("key 1 should still exist")
    end

    match tree.get(3)
    | let tv: _TestVal box => h.assert_true(tv.v == 3)
    else h.fail("key 3 should still exist")
    end

    // Delete non-existent key
    tree.delete(999)
    h.assert_true(tree.size() == 2)

    // Delete all
    tree.delete(1)
    tree.delete(3)
    h.assert_true(tree.is_empty())


class iso _TestArtKeys is UnitTest
  """
  Test in-order key iteration.
  """
  fun name(): String => "art/Keys iteration"

  fun apply(h: TestHelper) =>
    let tree = ArtTree[_TestVal]

    // Insert in random order
    let vals: Array[USize] = [100; 50; 200; 25; 75; 150; 250]
    for v in vals.values() do
      tree.insert(v, _TestVal(v))
    end
    h.assert_true(tree.size() == 7)

    // Keys should be in sorted order via lazy iterator
    let expected: Array[USize] = [25; 50; 75; 100; 150; 200; 250]
    let ks = tree.keys()
    var count: USize = 0
    while ks.has_next() do
      try
        let k = ks.next()?
        h.assert_true(k == expected(count)?,
          "expected " + expected(count)?.string() + " got " + k.string())
      else
        h.fail("key access error at index " + count.string())
      end
      count = count + 1
    end
    h.assert_true(count == 7, "expected 7 keys, got " + count.string())


class iso _TestArtNodeGrowth is UnitTest
  """
  Test node growth: insert enough keys to trigger Node4 -> Node16 -> Node48 -> Node256.
  """
  fun name(): String => "art/Node growth"

  fun apply(h: TestHelper) =>
    let tree = ArtTree[_TestVal]

    // Insert 300 keys (forces growth through all node types)
    var i: USize = 0
    while i < 300 do
      tree.insert(i, _TestVal(i))
      i = i + 1
    end
    h.assert_true(tree.size() == 300,
      "expected 300, got " + tree.size().string())

    // Verify all keys retrievable
    i = 0
    while i < 300 do
      match tree.get(i)
      | let tv: _TestVal box =>
        h.assert_true(tv.v == i, "value mismatch at key " + i.string())
      else
        h.fail("missing key " + i.string())
      end
      i = i + 1
    end

    // Keys should be sorted (via lazy iterator)
    let ks = tree.keys()
    i = 0
    while ks.has_next() do
      try
        let k = ks.next()?
        h.assert_true(k == i, "key mismatch at " + i.string())
      end
      i = i + 1
    end
    h.assert_true(i == 300, "expected 300 keys from iterator")

    // Delete some and verify shrinkage
    i = 0
    while i < 200 do
      tree.delete(i)
      i = i + 1
    end
    h.assert_true(tree.size() == 100,
      "after delete: expected 100, got " + tree.size().string())

    // Remaining keys should still be accessible
    i = 200
    while i < 300 do
      match tree.get(i)
      | let tv: _TestVal box =>
        h.assert_true(tv.v == i)
      else
        h.fail("missing key after shrink: " + i.string())
      end
      i = i + 1
    end


class iso _TestArtPathCompression is UnitTest
  """
  Test path compression: keys sharing long common prefixes.
  """
  fun name(): String => "art/Path compression"

  fun apply(h: TestHelper) =>
    let tree = ArtTree[_TestVal]

    // Keys with long common prefix in high bytes
    let base: USize = 0xDEADBEEF00000000
    tree.insert(base or 1, _TestVal(1))
    tree.insert(base or 2, _TestVal(2))
    tree.insert(base or 255, _TestVal(255))
    h.assert_true(tree.size() == 3)

    match tree.get(base or 1)
    | let tv: _TestVal box => h.assert_true(tv.v == 1)
    else h.fail("missing prefix key 1")
    end

    match tree.get(base or 255)
    | let tv: _TestVal box => h.assert_true(tv.v == 255)
    else h.fail("missing prefix key 255")
    end

    // Unrelated key should not be found
    h.assert_true(tree.get(0xCAFEBABE00000001) is None)


class iso _TestArtOverwrite is UnitTest
  """
  Test overwriting an existing key.
  """
  fun name(): String => "art/Overwrite"

  fun apply(h: TestHelper) =>
    let tree = ArtTree[_TestVal]
    tree.insert(42, _TestVal(100))
    h.assert_true(tree.size() == 1)

    // Overwrite
    tree.insert(42, _TestVal(200))
    h.assert_true(tree.size() == 1, "size should still be 1 after overwrite")

    match tree.get(42)
    | let tv: _TestVal box => h.assert_true(tv.v == 200,
        "expected 200 after overwrite, got " + tv.v.string())
    else h.fail("missing key after overwrite")
    end


class iso _TestArtClear is UnitTest
  """
  Test clearing the tree.
  """
  fun name(): String => "art/Clear"

  fun apply(h: TestHelper) =>
    let tree = ArtTree[_TestVal]
    var i: USize = 0
    while i < 50 do
      tree.insert(i, _TestVal(i))
      i = i + 1
    end
    h.assert_true(tree.size() == 50)

    tree.clear()
    h.assert_true(tree.is_empty())
    h.assert_true(tree.size() == 0)
    h.assert_true(tree.get(0) is None)
    h.assert_true(tree.keys().has_next() == false)


class iso _TestArtDuplicateInsert is UnitTest
  """
  Test inserting the same element multiple times with the same key.
  """
  fun name(): String => "art/Duplicate insert"

  fun apply(h: TestHelper) =>
    let tree = ArtTree[_TestVal]
    
    // Insert a key once
    tree.insert(42, _TestVal(100))
    h.assert_true(tree.size() == 1)
    
    // Insert the same key again with same value
    tree.insert(42, _TestVal(100))
    h.assert_true(tree.size() == 1, "size should still be 1 after duplicate insert")
    
    // Insert the same key again with different value
    tree.insert(42, _TestVal(200))
    h.assert_true(tree.size() == 1, "size should still be 1 after another duplicate insert")
    
    // Verify the final value is the last one inserted
    match tree.get(42)
    | let tv: _TestVal box => h.assert_true(tv.v == 200, "expected final value 200")
    else h.fail("missing key after duplicate inserts")
    end
    
    // Test with multiple duplicate inserts
    let key: USize = 123
    let value = _TestVal(999)
    var i: USize = 0
    while i < 10 do
      tree.insert(key, value)
      h.assert_true(tree.size() == 2, "size should remain 2 after multiple duplicate inserts")
      i = i + 1
    end
    
    // Verify the value is still correct
    match tree.get(key)
    | let tv: _TestVal box => h.assert_true(tv.v == 999)
    else h.fail("missing key after multiple duplicate inserts")
    end
    
    // Verify keys() only contains unique keys
    let keys = tree.keys()
    var key_count: USize = 0
    while keys.has_next() do
      try keys.next()? end
      key_count = key_count + 1
    end
    h.assert_true(key_count == 2, "keys() should return only unique keys")


class iso _TestArtCollectionsAPI is UnitTest
  """
  Test ART's collections-style API (update, insert returning values).
  """
  fun name(): String => "art/Collections API"

  fun apply(h: TestHelper) ? =>
    let tree = ArtTree[_TestVal]
    
    // Test insert returning value for reuse
    let val1 = _TestVal(100)
    let returned_val1 = tree.insert(42, consume val1)
    h.assert_true(returned_val1.v == 100, "insert should return the inserted value")
    h.assert_true(tree.size() == 1)
    
    // Test update returning previous value
    let val2 = _TestVal(200)
    let old_val = tree.update(42, consume val2)
    match old_val
    | let old: _TestVal => 
      h.assert_true(old.v == 100, "update should return previous value")
      h.assert_true(tree.size() == 1, "size should remain 1 after update")
    else
      h.fail("update should return previous value for existing key")
    end
    
    // Verify new value is stored
    match tree.get(42)
    | let current: _TestVal box => 
      h.assert_true(current.v == 200, "value should be updated to 200")
    else
      h.fail("key 42 should still exist")
    end
    
    // Test update on new key returns None
    let val3 = _TestVal(300)
    let no_old_val = tree.update(123, consume val3)
    h.assert_true(no_old_val is None, "update on new key should return None")
    h.assert_true(tree.size() == 2, "size should increase to 2")
    
    // Test insert_if_absent on new key
    let val4 = _TestVal(400)
    let inserted_val = tree.insert_if_absent(456, consume val4)
    h.assert_true(inserted_val.v == 400, "insert_if_absent should return inserted value for new key")
    h.assert_true(tree.size() == 3)
    
    // Test insert_if_absent on existing key
    let val5 = _TestVal(500)
    let existing_val = tree.insert_if_absent(42, consume val5)
    h.assert_true(existing_val.v == 200, "insert_if_absent should return existing value for duplicate key")
    h.assert_true(tree.size() == 3, "size should remain 3")
    
    // Verify existing value wasn't overwritten
    match tree.get(42)
    | let current: _TestVal box => 
      h.assert_true(current.v == 200, "existing value should not be overwritten by insert_if_absent")
    else
      h.fail("key 42 should still exist")
    end
    
    // Test value reuse pattern
    let reusable_val = _TestVal(600)
    let returned_reusable = tree.insert(789, consume reusable_val)
    // The returned value should be the same object (allowing reuse)
    h.assert_true(returned_reusable.v == 600)
    
    // Test chaining operations
    let initial_val = _TestVal(1000)
    let chain_result = tree.insert(999, consume initial_val)
    let update_result = tree.update(999, _TestVal(1001))
    
    h.assert_true(chain_result.v == 1000)
    match update_result
    | let old: _TestVal => h.assert_true(old.v == 1000)
    else h.fail("update should return previous value")
    end

    // Test lazy iterators
    let simple_tree = ArtTree[_TestVal]
    simple_tree.insert(1, _TestVal(10))
    simple_tree.insert(2, _TestVal(20))

    h.assert_true(simple_tree.size() == 2)

    // Test values() iterator
    let value_iter = simple_tree.values()
    h.assert_true(value_iter.has_next())
    let first_value = value_iter.next()?
    h.assert_true(first_value.v == 10)
    let second_value = value_iter.next()?
    h.assert_true(second_value.v == 20)
    h.assert_true(value_iter.has_next() == false)

    // Test pairs() iterator
    let pair_iter = simple_tree.pairs()
    h.assert_true(pair_iter.has_next())
    let first_pair = pair_iter.next()?
    h.assert_true(first_pair._1 == 1)
    h.assert_true(first_pair._2.v == 10)
    let second_pair = pair_iter.next()?
    h.assert_true(second_pair._1 == 2)
    h.assert_true(second_pair._2.v == 20)
    h.assert_true(pair_iter.has_next() == false)

    // Test with empty tree
    let empty_tree2 = ArtTree[_TestVal]
    let empty_values = empty_tree2.values()
    h.assert_true(empty_values.has_next() == false)

    let empty_pairs = empty_tree2.pairs()
    h.assert_true(empty_pairs.has_next() == false)


class iso _TestArtReverseIterators is UnitTest
  """
  Test reverse iterators: rkeys(), rvalues(), rpairs().
  """
  fun name(): String => "art/Reverse iterators"

  fun apply(h: TestHelper) ? =>
    let tree = ArtTree[_TestVal]

    let vals: Array[USize] = [100; 50; 200; 25; 75; 150; 250]
    for v in vals.values() do
      tree.insert(v, _TestVal(v))
    end

    // rkeys() should yield keys in descending order
    let expected: Array[USize] = [250; 200; 150; 100; 75; 50; 25]
    let rk = tree.rkeys()
    var count: USize = 0
    while rk.has_next() do
      let k = rk.next()?
      h.assert_true(k == expected(count)?,
        "rkeys: expected " + expected(count)?.string() + " got " + k.string())
      count = count + 1
    end
    h.assert_true(count == 7, "rkeys: expected 7 keys, got " + count.string())

    // rvalues() should yield values in descending key order
    let rv = tree.rvalues()
    count = 0
    while rv.has_next() do
      let v = rv.next()?
      h.assert_true(v.v == expected(count)?,
        "rvalues: mismatch at " + count.string())
      count = count + 1
    end
    h.assert_true(count == 7)

    // rpairs() should yield pairs in descending key order
    let rp = tree.rpairs()
    count = 0
    while rp.has_next() do
      (let k, let v) = rp.next()?
      h.assert_true(k == expected(count)?,
        "rpairs key: expected " + expected(count)?.string() + " got " + k.string())
      h.assert_true(v.v == expected(count)?)
      count = count + 1
    end
    h.assert_true(count == 7)

    // Empty tree reverse iterators
    let empty = ArtTree[_TestVal]
    h.assert_true(empty.rkeys().has_next() == false)
    h.assert_true(empty.rvalues().has_next() == false)
    h.assert_true(empty.rpairs().has_next() == false)


class iso _TestArtIteratorRewind is UnitTest
  """
  Test rewind() on forward and reverse iterators.
  """
  fun name(): String => "art/Iterator rewind"

  fun apply(h: TestHelper) ? =>
    let tree = ArtTree[_TestVal]
    tree.insert(10, _TestVal(10))
    tree.insert(20, _TestVal(20))
    tree.insert(30, _TestVal(30))

    // Forward keys: exhaust then rewind
    let fk = tree.keys()
    h.assert_true(fk.next()? == 10)
    h.assert_true(fk.next()? == 20)
    h.assert_true(fk.next()? == 30)
    h.assert_true(fk.has_next() == false)

    fk.rewind()
    h.assert_true(fk.has_next())
    h.assert_true(fk.next()? == 10)
    h.assert_true(fk.next()? == 20)
    h.assert_true(fk.next()? == 30)
    h.assert_true(fk.has_next() == false)

    // Reverse keys: exhaust then rewind
    let rk = tree.rkeys()
    h.assert_true(rk.next()? == 30)
    h.assert_true(rk.next()? == 20)
    h.assert_true(rk.next()? == 10)
    h.assert_true(rk.has_next() == false)

    rk.rewind()
    h.assert_true(rk.has_next())
    h.assert_true(rk.next()? == 30)
    h.assert_true(rk.next()? == 20)
    h.assert_true(rk.next()? == 10)
    h.assert_true(rk.has_next() == false)

    // Partial iteration then rewind
    let fv = tree.values()
    h.assert_true(fv.next()?.v == 10)
    fv.rewind()
    h.assert_true(fv.next()?.v == 10)
    h.assert_true(fv.next()?.v == 20)

    // Pairs rewind
    let fp = tree.pairs()
    (let k1, let v1) = fp.next()?
    h.assert_true(k1 == 10)
    fp.rewind()
    (let k1b, let v1b) = fp.next()?
    h.assert_true(k1b == 10)
