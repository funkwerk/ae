/**
 * Very simple write-only API for building XML documents.
 * Abuses operator overloading to allow a very terse syntax.
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

module ae.utils.xmlbuild;

import ae.utils.xmllite : XmlNode, XmlNodeType;
import ae.utils.xmlwriter;

/// Create an XML node. Entry point.
XmlBuildNode newXml()
{
	return new XmlBuildNode();
}

/// The node type. Avoid using directly.
// Can't use struct pointers, because node["attr"] is
// interpreted as indexing the pointer.
final class XmlBuildNode
{
	/// Create a child node by calling a "method" on the node
	XmlBuildNode opDispatch(string name)(string[string] attributes = null)
	{
		auto result = new XmlBuildNode();
		result._xmlbuild_info.tag = name;
		foreach (key, value; attributes)
			result._xmlbuild_info.attributes ~= StringPair(key, value);
		_xmlbuild_info.children ~= result;
		return result;
	}

	/// Add attribute by assigning a "field" on the node
	@property string opDispatch(string name)(string value)
	{
		_xmlbuild_info.attributes ~= StringPair(name, value);
		return value;
	}

	/// Add attribute via index
	string opIndexAssign(string value, string name)
	{
		_xmlbuild_info.attributes ~= StringPair(name, value);
		return value;
	}

	/// Set inner text via assigning a string
	void opAssign(string text)
	{
		_xmlbuild_info.text = text;
	}

	XmlBuildNode append(XmlNode node)
	{
		import std.algorithm : map, each;
		import std.range : array;

		auto result = new XmlBuildNode();

		if (node.type == XmlNodeType.Text)
		{
			result._xmlbuild_info.tag = null;
			result._xmlbuild_info.text = node.tag;
		}
		else
		{
			result._xmlbuild_info.tag = node.tag;
			foreach (key, value; node.attributes)
				result._xmlbuild_info.attributes ~= StringPair(key, value);
			node.children.each!(node => result.append(node));
		}

		this._xmlbuild_info.children ~= result;

		return result;
	}

	override string toString() const
	{
		XmlWriter writer;
		writeTo(writer);
		return writer.output.get();
	}

	string toPrettyString() const
	{
		PrettyXmlWriter writer;
		writeTo(writer);
		return writer.output.get();
	}

	final void writeTo(XmlWriter)(ref XmlWriter output) const
	{
		with (_xmlbuild_info)
		{
			if (tag)
			{
				output.startTagWithAttributes(tag);
				foreach (ref attribute; attributes)
					output.addAttribute(attribute.key, attribute.value);
				if (!children.length && !text)
				{
					output.endAttributesAndTag();
					return;
				}
				output.endAttributes();

				foreach (child; children)
					child.writeTo(output);
				output.text(text);

				output.endTag(tag);
			}
			else
			{
				assert(!attributes && !children);
				output.text(text);
			}
		}
	}

	// Use a unique name, unlikely to occur in an XML file as a field or attribute.
	private XmlBuildInfo _xmlbuild_info;
}

private:

struct StringPair { string key, value; }

struct XmlBuildInfo
{
	string tag, text;
	StringPair[] attributes;
	XmlBuildNode[] children;
}

unittest
{
	auto svg = newXml().svg();
	svg.xmlns = "http://www.w3.org/2000/svg";
	svg["version"] = "1.1";
	auto text = svg.text(["x" : "0", "y" : "15", "fill" : "red"]);
	text = "I love SVG";

	auto s = svg.toString();
	string s1 = `<svg xmlns="http://www.w3.org/2000/svg" version="1.1"><text fill="red" x="0" y="15">I love SVG</text></svg>`;
	string s2 = `<svg xmlns="http://www.w3.org/2000/svg" version="1.1"><text x="0" y="15" fill="red">I love SVG</text></svg>`;
	assert(s == s1 || s == s2, s);
}
