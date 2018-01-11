/**
 * Array utility functions
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 */

module ae.utils.array;

import std.algorithm.iteration;
import std.algorithm.mutation;
import std.algorithm.searching;
import std.algorithm.sorting;
import std.array;
import std.exception;
import std.format;
import std.traits;

import ae.utils.meta;

public import ae.utils.aa;
public import ae.utils.appender;

/// Slice a variable.
T[] toArray(T)(ref T v)
{
	return (&v)[0..1];
}

/// Return the value represented as an array of bytes.
@property inout(ubyte)[] bytes(T)(ref inout(T) value)
	if (!hasIndirections!T)
{
	return value.toArray().bytes;
}

/// ditto
@property inout(ubyte)[] bytes(T)(inout(T) value)
	if (is(T U : U[]) && !hasIndirections!U)
{
	return cast(inout(ubyte)[])value;
}

unittest
{
	ubyte b = 5;
	assert(b.bytes == [5]);

	struct S { ubyte b = 5; }
	S s;
	assert(s.bytes == [5]);

	ubyte[1] sa = [5];
	assert(sa.bytes == [5]);
}

/// Reverse of bytes()
ref inout(T) fromBytes(T)(inout(ubyte)[] bytes)
	if (!hasIndirections!T)
{
	assert(bytes.length == T.sizeof, "Data length mismatch for %s".format(T.stringof));
	return *cast(inout(T)*)bytes.ptr;
}

/// ditto
inout(T) fromBytes(T)(inout(ubyte)[] bytes)
	if (is(T U : U[]) && !hasIndirections!U)
{
	return cast(inout(T))bytes;
}

unittest
{
	{       ubyte b = 5; assert(b.bytes.fromBytes!ubyte == 5); }
	{ const ubyte b = 5; assert(b.bytes.fromBytes!ubyte == 5); }
	struct S { ubyte b; }
	{       ubyte b = 5; assert(b.bytes.fromBytes!S == S(5)); }
}

unittest
{
	struct S { ubyte a, b; }
	ubyte[] arr = [1, 2];
	assert(arr.fromBytes!S == S(1, 2));
	assert(arr.fromBytes!(S[]) == [S(1, 2)]);
}

int memcmp(in ubyte[] a, in ubyte[] b)
{
	assert(a.length == b.length);
	import core.stdc.string : memcmp;
	return memcmp(a.ptr, b.ptr, a.length);
}

/// Like std.algorithm.copy, but without the auto-decode bullshit.
/// https://issues.dlang.org/show_bug.cgi?id=13650
void memmove(T)(T[] dst, in T[] src)
{
	assert(src.length == dst.length);
	import core.stdc.string : memmove;
	memmove(dst.ptr, src.ptr, dst.length * T.sizeof);
}

T[] vector(string op, T)(T[] a, T[] b)
{
	assert(a.length == b.length);
	T[] result = new T[a.length];
	foreach (i, ref r; result)
		r = mixin("a[i]" ~ op ~ "b[i]");
	return result;
}

T[] vectorAssign(string op, T)(T[] a, T[] b)
{
	assert(a.length == b.length);
	foreach (i, ref r; a)
		mixin("r " ~ op ~ "= b[i];");
	return a;
}

T[] padRight(T)(T[] s, size_t l, T c)
{
	auto ol = s.length;
	if (ol < l)
	{
		s.length = l;
		s[ol..$] = c;
	}
	return s;
}

T[] repeatOne(T)(T c, size_t l)
{
	T[] result = new T[l];
	result[] = c;
	return result;
}

/// Complement to std.string.indexOf which works with arrays
/// of non-character types.
/// Unlike std.algorithm.countUntil, it does not auto-decode,
/// and returns an index usable for array indexing/slicing.
sizediff_t indexOf(T, D)(in T[] arr, in D val)
//	if (!isSomeChar!T)
	if (!isSomeChar!T && is(typeof(arr.countUntil(val))) && is(typeof(arr[0]==val)))
{
	//assert(arr[0]==val);
	return arr.countUntil(val);
}

sizediff_t indexOf(T)(in T[] arr, in T[] val) /// ditto
	if (!isSomeChar!T && is(typeof(arr.countUntil(val))))
{
	return arr.countUntil(val);
}

/// Index of element, no BS.
sizediff_t indexOfElement(T, D)(in T[] arr, auto ref in D val)
	if (is(typeof(arr[0]==val)))
{
	foreach (i, ref v; arr)
		if (v == val)
			return i;
	return -1;
}

/// Whether array contains value, no BS.
bool contains(T, V)(in T[] arr, auto ref in V val)
	if (is(typeof(arr[0]==val)))
{
	return arr.indexOfElement(val) >= 0;
}

/// Like startsWith, but with an offset.
bool containsAt(T)(in T[] haystack, in T[] needle, size_t offset)
{
	return haystack.length >= offset + needle.length
		&& haystack[offset..offset+needle.length] == needle;
}

unittest
{
	assert( "abracadabra".containsAt("ada", 5));
	assert(!"abracadabra".containsAt("ada", 6));
	assert(!"abracadabra".containsAt("ada", 99));
}

bool isIn(T)(T val, in T[] arr)
{
	return arr.contains(val);
}

bool isOneOf(T)(T val, T[] arr...)
{
	return arr.contains(val);
}

/// Like AA.get - soft indexing, throws an
/// Exception (not an Error) on out-of-bounds,
/// even in release builds.
ref T get(T)(T[] arr, size_t index)
{
	enforce(index < arr.length, "Out-of-bounds array access");
	return arr[index];
}

/// Like AA.get - soft indexing, returns
/// default value on out-of-bounds.
auto get(T)(T[] arr, size_t index, auto ref T defaultValue)
{
	if (index >= arr.length)
		return defaultValue;
	return arr[index];
}

/// Expand the array if index is out-of-bounds.
ref T getExpand(T)(ref T[] arr, size_t index)
{
	if (index >= arr.length)
		arr.length = index + 1;
	return arr[index];
}

/// ditto
ref T putExpand(T)(ref T[] arr, size_t index, auto ref T value)
{
	if (index >= arr.length)
		arr.length = index + 1;
	return arr[index] = value;
}

/// Slices an array. Throws an Exception (not an Error)
/// on out-of-bounds, even in release builds.
T[] slice(T)(T[] arr, size_t p0, size_t p1)
{
	enforce(p0 < p1 && p1 < arr.length, "Out-of-bounds array slice");
	return arr[p0..p1];
}

/// Given an array and its slice, returns the
/// start index of the slice inside the array.
size_t sliceIndex(T)(in T[] arr, in T[] slice)
{
	auto a = arr.ptr;
	auto b = a + arr.length;
	auto p = slice.ptr;
	assert(a <= p && p <= b, "Out-of-bounds array slice");
	return p - a;
}

/// Like std.array.split, but returns null if val was empty.
auto splitEmpty(T, S)(T value, S separator)
{
	return value.length ? split(value, separator) : null;
}

import std.random;

/// Select and return a random element from the array.
auto ref sample(T)(T[] arr)
{
	return arr[uniform(0, $)];
}

unittest
{
	assert([7, 7, 7].sample == 7);
	auto s = ["foo", "bar"].sample(); // Issue 13807
	const(int)[] a2 = [5]; sample(a2);
}

/// Select and return a random element from the array,
/// and remove it from the array.
T pluck(T)(ref T[] arr)
{
	auto pos = uniform(0, arr.length);
	auto result = arr[pos];
	arr = arr.remove(pos);
	return result;
}

unittest
{
	auto arr = [1, 2, 3];
	auto res = [arr.pluck, arr.pluck, arr.pluck];
	res.sort();
	assert(res == [1, 2, 3]);
}

import std.functional;

T[] countSort(alias value = "a", T)(T[] arr)
{
	alias unaryFun!value getValue;
	alias typeof(getValue(arr[0])) V;
	if (arr.length == 0) return arr;
	V min = getValue(arr[0]), max = getValue(arr[0]);
	foreach (el; arr[1..$])
	{
		auto v = getValue(el);
		if (min > v)
			min = v;
		if (max < v)
			max = v;
	}
	auto n = max-min+1;
	auto counts = new size_t[n];
	foreach (el; arr)
		counts[getValue(el)-min]++;
	auto indices = new size_t[n];
	foreach (i; 1..n)
		indices[i] = indices[i-1] + counts[i-1];
	T[] result = new T[arr.length];
	foreach (el; arr)
		result[indices[getValue(el)-min]++] = el;
	return result;
}

// ***************************************************************************

void stackPush(T)(ref T[] arr, T val)
{
	arr ~= val;
}
alias stackPush queuePush;

T stackPeek(T)(T[] arr) { return arr[$-1]; }

T stackPop(T)(ref T[] arr)
{
	auto ret = arr[$-1];
	arr = arr[0..$-1];
	return ret;
}

T queuePeek(T)(T[] arr) { return arr[0]; }

T queuePeekLast(T)(T[] arr) { return arr[$-1]; }

T queuePop(T)(ref T[] arr)
{
	auto ret = arr[0];
	arr = arr[1..$];
	if (!arr.length) arr = null;
	return ret;
}

T shift(T)(ref T[] arr) { T result = arr[0]; arr = arr[1..$]; return result; }
T[] shift(T)(ref T[] arr, size_t n) { T[] result = arr[0..n]; arr = arr[n..$]; return result; }
T[N] shift(size_t N, T)(ref T[] arr) { T[N] result = cast(T[N])(arr[0..N]); arr = arr[N..$]; return result; }
void unshift(T)(ref T[] arr, T value) { arr.insertInPlace(0, value); }
void unshift(T)(ref T[] arr, T[] value) { arr.insertInPlace(0, value); }

unittest
{
	int[] arr = [1, 2, 3];
	assert(arr.shift == 1);
	assert(arr == [2, 3]);
	assert(arr.shift(2) == [2, 3]);
	assert(arr == []);

	arr = [3];
	arr.unshift([1, 2]);
	assert(arr == [1, 2, 3]);
	arr.unshift(0);
	assert(arr == [0, 1, 2, 3]);

	assert(arr.shift!2 == [0, 1]);
	assert(arr == [2, 3]);
}

/// If arr starts with prefix, slice it off and return true.
/// Otherwise leave arr unchaned and return false.
deprecated("Use std.algorithm.skipOver instead")
bool eat(T)(ref T[] arr, T[] prefix)
{
	if (arr.startsWith(prefix))
	{
		arr = arr[prefix.length..$];
		return true;
	}
	return false;
}

/// Returns the slice of source up to the first occurrence of delim,
/// and fast-forwards source to the point after delim.
/// If delim is not found, the behavior depends on orUntilEnd:
/// - If orUntilEnd is false (default), it returns null
///   and leaves source unchanged.
/// - If orUntilEnd is true, it returns source,
///   and then sets source to null.
T[] skipUntil(T, D)(ref T[] source, D delim, bool orUntilEnd = false)
{
	enum bool isSlice = is(typeof(source[0..1]==delim));
	enum bool isElem  = is(typeof(source[0]   ==delim));
	static assert(isSlice || isElem, "Can't skip " ~ T.stringof ~ " until " ~ D.stringof);
	static assert(isSlice != isElem, "Ambiguous types for skipUntil: " ~ T.stringof ~ " and " ~ D.stringof);
	static if (isSlice)
		auto delimLength = delim.length;
	else
		enum delimLength = 1;

	static if (is(typeof(ae.utils.array.indexOf(source, delim))))
		alias indexOf = ae.utils.array.indexOf;
	else
	static if (is(typeof(std.string.indexOf(source, delim))))
		alias indexOf = std.string.indexOf;

	auto i = indexOf(source, delim);
	if (i < 0)
	{
		if (orUntilEnd)
		{
			auto result = source;
			source = null;
			return result;
		}
		else
			return null;
	}
	auto result = source[0..i];
	source = source[i+delimLength..$];
	return result;
}

deprecated("Use skipUntil instead")
enum OnEof { returnNull, returnRemainder, throwException }

deprecated("Use skipUntil instead")
template eatUntil(OnEof onEof = OnEof.throwException)
{
	T[] eatUntil(T, D)(ref T[] source, D delim)
	{
		static if (onEof == OnEof.returnNull)
			return skipUntil(source, delim, false);
		else
		static if (onEof == OnEof.returnRemainder)
			return skipUntil(source, delim, true);
		else
			return skipUntil(source, delim, false).enforce("Delimiter not found in source");
	}
}

deprecated unittest
{
	string s;

	s = "Mary had a little lamb";
	assert(s.eatUntil(" ") == "Mary");
	assert(s.eatUntil(" ") == "had");
	assert(s.eatUntil(' ') == "a");

	assertThrown!Exception(s.eatUntil("#"));
	assert(s.eatUntil!(OnEof.returnNull)("#") is null);
	assert(s.eatUntil!(OnEof.returnRemainder)("#") == "little lamb");

	ubyte[] bytes = [1, 2, 0, 3, 4, 0, 0];
	assert(bytes.eatUntil(0) == [1, 2]);
	assert(bytes.eatUntil([ubyte(0), ubyte(0)]) == [3, 4]);
}

// ***************************************************************************

// Equivalents of array(xxx(...)), but less parens and UFCS-able.
auto amap(alias pred, T)(T[] arr) { return array(map!pred(arr)); }
auto afilter(alias pred, T)(T[] arr) { return array(filter!pred(arr)); }
auto auniq(T)(T[] arr) { return array(uniq(arr)); }
auto asort(alias pred, T)(T[] arr) { sort!pred(arr); return arr; }

unittest
{
	assert([1, 2, 3].amap!`a*2`() == [2, 4, 6]);
	assert([1, 2, 3].amap!(n => n*n)() == [1, 4, 9]);
}

// ***************************************************************************

/// Array with normalized comparison and hashing.
/// Params:
///   T = array element type to wrap.
///   normalize = function which should return a range of normalized elements.
struct NormalizedArray(T, alias normalize)
{
	T[] arr;

	this(T[] arr) { this.arr = arr; }

	int opCmp    (in T[]                 other) const { return std.algorithm.cmp(normalize(arr), normalize(other    ))   ; }
	int opCmp    (    const typeof(this) other) const { return std.algorithm.cmp(normalize(arr), normalize(other.arr))   ; }
	int opCmp    (ref const typeof(this) other) const { return std.algorithm.cmp(normalize(arr), normalize(other.arr))   ; }
	bool opEquals(in T[]                 other) const { return std.algorithm.cmp(normalize(arr), normalize(other    ))==0; }
	bool opEquals(    const typeof(this) other) const { return std.algorithm.cmp(normalize(arr), normalize(other.arr))==0; }
	bool opEquals(ref const typeof(this) other) const { return std.algorithm.cmp(normalize(arr), normalize(other.arr))==0; }

	hash_t toHashReal() const
	{
		import std.digest.crc;
		CRC32 crc;
		foreach (c; normalize(arr))
			crc.put(cast(ubyte[])((&c)[0..1]));
		static union Result { ubyte[4] crcResult; hash_t hash; }
		return Result(crc.finish()).hash;
	}

	hash_t toHash() const nothrow @trusted
	{
		return (cast(hash_t delegate() nothrow @safe)&toHashReal)();
	}
}

// ***************************************************************************

/// Equivalent of PHP's `list` language construct:
/// http://php.net/manual/en/function.list.php
/// Works with arrays and tuples.
/// Specify `null` as an argument to ignore that index
/// (equivalent of `list(x, , y)` in PHP).
auto list(Args...)(auto ref Args args)
{
	struct List
	{
		auto dummy() { return args[0]; }
		void opAssign(T)(auto ref T t)
		{
			assert(t.length == args.length,
				"Assigning %d elements to list with %d elements"
				.format(t.length, args.length));
			foreach (i; RangeTuple!(Args.length))
				static if (!is(Args[i] == typeof(null)))
					args[i] = t[i];
		}
	}
	return List();
}

///
unittest
{
	string name, value;
	list(name, null, value) = "NAME=VALUE".findSplit("=");
	assert(name == "NAME" && value == "VALUE");
}
