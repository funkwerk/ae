﻿/**
 * Light read-only XML library
 * May be deprecated in the future.
 * See other XML modules for better implementations.
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 *   Simon Arlott
 */

module ae.utils.xmllite;

// TODO: better/safer handling of malformed XML

import std.ascii;
import std.algorithm;
import std.exception;
import std.string;

import ae.utils.array;
import ae.utils.exception;
import ae.utils.xmlwriter;

// ************************************************************************

/// std.stream.Stream-like type with bonus speed
private struct StringStream
{
	string s;
	size_t position;

	@disable this();
	@disable this(this);
	this(string s)
	{
		enum ditch = "'\">\0\0\0\0\0"; // Dirty precaution
		this.s = (s ~ ditch)[0..$-ditch.length];
	}

	char read() { return s[position++]; }
	@property size_t size() { return s.length; }
}

// ************************************************************************

mixin DeclareException!q{XmlParseException};

enum XmlNodeType
{
	None,
	Root,
	Node,
	Comment,
	Meta,
	DocType,
	CData,
	Text
}

class XmlNode
{
	string tag;
	string namespace;
	OrderedMap!(string, string) attributes;
	XmlNode parent;
	XmlNode[] children;
	XmlNodeType type;
	ulong startPos, endPos;

	this(ref StringStream s) { parseInto!XmlParseConfig(this, s); }
	this(string s) { auto ss = StringStream(s); this(ss); }

	this(XmlNodeType type = XmlNodeType.None, string tag = null, string namespace = null)
	{
		this.namespace = namespace;
		this.type = type;
		this.tag = tag;
	}

	@property void name(string name)
	{
		if (auto split = name.findSplit(":"))
		{
			this.namespace = split[0];
			this.tag = split[2];
		}
		else
		{
			this.tag = name;
		}
	}

	@property string name() const
	{
		if (this.namespace.length > 0)
		{
			return format!"%s:%s"(this.namespace, this.tag);
		}
		return this.tag;
	}

	XmlNode addAttribute(string name, string value)
	{
		attributes[name] = value;
		return this;
	}

	XmlNode addChild(XmlNode child)
	{
		child.parent = this;
		children ~= child;
		return this;
	}

	override string toString() const
	{
		XmlWriter writer;
		writeTo(writer);
		return writer.output.get();
	}

	final void writeTo(XmlWriter)(ref XmlWriter output) const
	{
		void writeChildren()
		{
			foreach (child; children)
				child.writeTo(output);
		}

		void writeAttributes()
		{
			foreach (key, value; attributes)
				output.addAttribute(key, value);
		}

		final switch (type)
		{
			case XmlNodeType.None:
				assert(false);
			case XmlNodeType.Root:
				writeChildren();
				return;
			case XmlNodeType.Node:
				output.startTagWithAttributes(name);
				writeAttributes();
				if (children.length)
				{
					bool oneLine = children.length == 1 && children[0].type == XmlNodeType.Text;
					if (oneLine)
						output.formatter.enabled = false;
					output.endAttributes();
					writeChildren();
					output.endTag(name);
					if (oneLine)
					{
						output.formatter.enabled = true;
						output.newLine();
					}
				}
				else
					output.endAttributesAndTag();
				return;
			case XmlNodeType.Meta:
				assert(children.length == 0);
				output.startPI(tag);
				writeAttributes();
				output.endPI();
				return;
			case XmlNodeType.DocType:
				assert(children.length == 0);
				output.doctype(tag);
				return;
			case XmlNodeType.Text:
				output.text(tag);
				return;
			case XmlNodeType.Comment:
				// TODO
				return;
			case XmlNodeType.CData:
				output.text(tag);
				return;
		}
	}

	@property string text()
	{
		final switch (type)
		{
			case XmlNodeType.None:
				assert(false);
			case XmlNodeType.Text:
			case XmlNodeType.CData:
				return tag;
			case XmlNodeType.Node:
			case XmlNodeType.Root:
				string result;
				if (tag == "br")
					result = "\n";
				foreach (child; children)
					result ~= child.text();
				return result;
			case XmlNodeType.Comment:
			case XmlNodeType.Meta:
			case XmlNodeType.DocType:
				return null;
		}
	}

	final XmlNode findChild(string name)
	{
		if (auto parts = name.findSplit(":"))
		{
			auto namespace = parts[0];
			auto tag = parts[2];
			foreach (child; children)
				if (child.type == XmlNodeType.Node && child.tag == tag && child.namespace == namespace)
					return child;
		}
		else
		{
			foreach (child; children)
				if (child.type == XmlNodeType.Node && child.tag == name)
					return child;
		}
		return null;
	}

	final XmlNode[] findChildren(string name)
	{
		XmlNode[] result;
		if (auto parts = name.findSplit(":"))
		{
			auto namespace = parts[0];
			auto tag = parts[2];
			foreach (child; children)
				if (child.type == XmlNodeType.Node && child.tag == tag && child.namespace == namespace)
					result ~= child;
		}
		else
		{
			foreach (child; children)
				if (child.type == XmlNodeType.Node && child.tag == name)
					result ~= child;
		}
		return result;
	}

	final XmlNode opIndex(string name)
	{
		auto node = findChild(name);
		if (node is null)
			throw new XmlParseException("No such child: " ~ name);
		return node;
	}

	final XmlNode opIndex(string name, size_t index)
	{
		auto nodes = findChildren(name);
		if (index >= nodes.length)
			throw new XmlParseException(format("Can't get node with name %s and index %d, there are only %d children with that name", name, index, nodes.length));
		return nodes[index];
	}

	final XmlNode opIndex(size_t index)
	{
		return children[index];
	}

	final @property size_t length() { return children.length; }

	int opApply(int delegate(ref XmlNode) dg)
	{
		int result = 0;

		for (int i = 0; i < children.length; i++)
		{
			result = dg(children[i]);
			if (result)
				break;
		}
		return result;
	}

	final @property XmlNode dup()
	{
		auto result = new XmlNode(type, tag, namespace);
		result.attributes = attributes.dup;
		result.children.reserve(children.length);
		foreach (child; children)
			result.addChild(child.dup);
		return result;
	}
}

class XmlDocument : XmlNode
{
	this()
	{
		super(XmlNodeType.Root);
		tag = "<Root>";
	}

	this(ref StringStream s) { this(); parseInto!XmlParseConfig(this, s); }
	this(string s) { auto ss = StringStream(s); this(ss); }
}

/// The logic for how to handle a node's closing tags.
enum NodeCloseMode
{
	/// This element must always have an explicit closing tag
	/// (or a self-closing tag). An unclosed tag will lead to
	/// a parse error.
	/// In XML, all tags are "always".
	always,
/*
	/// Close tags are optional. When an element with a tag is
	/// encountered directly under an element with the same tag,
	/// it is assumed that the first element is closed before
	/// the second, so the two are siblings, not parent/child.
	/// Thus, `<p>a<p>b</p>` is parsed as `<p>a</p><p>b</p>`,
	/// not `<p>a<p>b</p></p>`, however `<p>a<div><p>b</div>` is
	/// still parsed as `<p>a<div><p>b</p></div></p>`.
	/// This mode can be used for relaxed HTML parsing.
	optional,
*/
	/// Close tags are optional, but are implied when absent.
	/// As a result, these elements cannot have any content,
	/// and any close tags must be adjacent to the open tag.
	implicit,

	/// This element is void and must never have a closing tag.
	/// It is always implicitly closed right after opening.
	/// A close tag is always an error.
	/// This mode can be used for strict parsing of HTML5 void
	/// elements.
	never,
}

/// Configuration for parsing XML.
struct XmlParseConfig
{
static:
	NodeCloseMode nodeCloseMode(string tag) { return NodeCloseMode.always; }
	enum optionalParameterValues = false;
}

/// Configuration for strict parsing of HTML5.
/// All void tags must never be closed, and all
/// non-void tags must always be explicitly closed.
/// Attributes must still be quoted like in XML.
struct Html5StrictParseConfig
{
static:
	immutable voidElements = [
		"area"   , "base"  , "br"   , "col" ,
		"command", "embed" , "hr"   , "img" ,
		"input"  , "keygen", "link" , "meta",
		"param"  , "source", "track", "wbr" ,
	];

	NodeCloseMode nodeCloseMode(string tag)
	{
		return tag.isOneOf(voidElements)
			? NodeCloseMode.never
			: NodeCloseMode.always
		;
	}

	enum optionalParameterValues = true;
}

/// Parse an SGML-ish string into an XmlNode
alias parse = parseString!XmlNode;

/// Parse an SGML-ish StringStream into an XmlDocument
alias parseDocument = parseString!XmlDocument;

alias xmlParse = parseDocument!XmlParseConfig;

private:

public // alias
template parseString(Node)
{
	Node parseString(Config)(string s)
	{
		auto ss = StringStream(s);
		alias f = parseStream!Node;
		return f!Config(ss);
	}
}

template parseStream(Node)
{
	Node parseStream(Config)(ref StringStream s)
	{
		auto n = new Node;
		parseInto!Config(n, s);
		return n;
	}
}

alias parseNode = parseStream!XmlNode;

/// Parse an SGML-ish StringStream into an XmlDocument
void parseInto(Config)(XmlDocument d, ref StringStream s)
{
	skipWhitespace(s);
	while (s.position < s.size)
		try
		{
			auto n = new XmlNode;
			parseInto!Config(n, s);
			d.addChild(n);
			skipWhitespace(s);
		}
		catch (XmlParseException e)
		{
			import std.algorithm.searching;
			import std.range : retro;

			auto head = s.s[0..s.position];
			auto row    = head.representation.count('\n');
			auto column = head.representation.retro.countUntil('\n');
			if (column < 0)
				column = head.length;
			throw new XmlParseException("Error at %d:%d (offset %d)".format(
				1 + row,
				1 + column,
				head.length,
			), e);
		}
}

/// Parse an SGML-ish StringStream into an XmlNode
void parseInto(Config)(XmlNode node, ref StringStream s)
{
	node.startPos = s.position;
	char c;
	do
		c = s.read();
	while (isWhiteChar[c]);

	if (c!='<')  // text node
	{
		node.type = XmlNodeType.Text;
		string text;
		while (c!='<')
		{
			// TODO: check for EOF
			text ~= c;
			c = s.read();
		}
		s.position--; // rewind to '<'
		node.tag = decodeEntities(text);
		//tag = tag.strip();
	}
	else
	{
		c = s.read();
		if (c=='!')
		{
			c = s.read();
			if (c == '-') // comment
			{
				expect(s, '-');
				node.type = XmlNodeType.Comment;
				string tag;
				do
				{
					c = s.read();
					tag ~= c;
				} while (tag.length<3 || tag[$-3..$] != "-->");
				tag = tag[0..$-3];
				node.tag = tag;
			}
			else
			if (c == '[') // CDATA
			{
				foreach (x; "CDATA[")
					expect(s, x);
				node.type = XmlNodeType.CData;
				string tag;
				do
				{
					c = s.read();
					tag ~= c;
				} while (tag.length<3 || tag[$-3..$] != "]]>");
				tag = tag[0..$-3];
				node.tag = tag;
			}
			else // doctype, etc.
			{
				node.type = XmlNodeType.DocType;
				while (c != '>')
				{
					node.tag ~= c;
					c = s.read();
				}
			}
		}
		else
		if (c=='?')
		{
			node.type = XmlNodeType.Meta;
			node.tag = readWord(s);
			if (node.tag.length==0) throw new XmlParseException("Invalid tag");
			while (true)
			{
				skipWhitespace(s);
				if (peek(s)=='?')
					break;
				readAttribute!Config(node, s);
			}
			c = s.read();
			expect(s, '>');
		}
		else
		if (c=='/')
			throw new XmlParseException("Unexpected close tag");
		else
		{
			node.type = XmlNodeType.Node;
			node.name = c~readWord(s);
			while (true)
			{
				skipWhitespace(s);
				c = peek(s);
				if (c=='>' || c=='/')
					break;
				readAttribute!Config(node, s);
			}
			c = s.read();

			auto closeMode = Config.nodeCloseMode(node.tag);
			if (closeMode == NodeCloseMode.never)
				enforce!XmlParseException(c=='>', "Self-closing void tag <%s>".format(node.tag));
			else
			if (closeMode == NodeCloseMode.implicit)
			{
				if (c == '/')
					expect(s, '>');
			}
			else
			{
				if (c=='>')
				{
					while (true)
					{
						while (true)
						{
							skipWhitespace(s);
							if (peek(s)=='<' && peek(s, 2)=='/')
								break;
							try
								node.addChild(parseNode!Config(s));
							catch (XmlParseException e)
								throw new XmlParseException("Error while processing child of "~node.tag, e);
						}
						expect(s, '<');
						expect(s, '/');
						auto word = readWord(s);
						if (word != node.name)
						{
							auto closeMode2 = Config.nodeCloseMode(word);
							if (closeMode2 == NodeCloseMode.implicit)
							{
								auto parent = node.parent;
								enforce!XmlParseException(parent, "Top-level close tag for implicitly-closed node </%s>".format(word));
								enforce!XmlParseException(parent.children.length, "First-child close tag for implicitly-closed node </%s>".format(word));
								enforce!XmlParseException(parent.children[$-1].name == word, "Non-empty implicitly-closed node <%s>".format(word));
								continue;
							}
							else
								enforce!XmlParseException(word == node.name, "Expected </%s>, not </%s>".format(node.name, word));
						}
						expect(s, '>');
						break;
					}
				}
				else // '/'
					expect(s, '>');
			}
		}
	}
	node.endPos = s.position;
}

private:

void readAttribute(Config)(XmlNode node, ref StringStream s)
{
	string name = readWord(s);
	if (name.length==0) throw new XmlParseException("Invalid attribute");
	skipWhitespace(s);

	static if (Config.optionalParameterValues)
	{
		if (peek(s) != '=')
		{
			node.attributes[name] = null;
			return;
		}
	}

	expect(s, '=');
	skipWhitespace(s);
	char delim;
	delim = s.read();
	if (delim != '\'' && delim != '"')
		throw new XmlParseException("Expected ' or \", not %s".format(delim));
	string value = readUntil(s, delim);
	node.attributes[name] = decodeEntities(value);
}

char peek(ref StringStream s, int n=1)
{
	return s.s[s.position + n - 1];
}

void skipWhitespace(ref StringStream s)
{
	while (isWhiteChar[s.s.ptr[s.position]])
		s.position++;
}

__gshared bool[256] isWhiteChar, isWordChar;

shared static this()
{
	foreach (c; 0..256)
	{
		isWhiteChar[c] = isWhite(c);
		isWordChar[c] = c=='-' || c=='_' || c==':' || isAlphaNum(c);
	}
}

string readWord(ref StringStream stream)
{
	auto start = stream.s.ptr + stream.position;
	auto end = stream.s.ptr + stream.s.length;
	auto p = start;
	while (p < end && isWordChar[*p])
		p++;
	auto len = p-start;
	stream.position += len;
	return start[0..len];
}

void expect(ref StringStream s, char c)
{
	char c2;
	c2 = s.read();
	enforce!XmlParseException(c==c2, "Expected " ~ c ~ ", got " ~ c2);
}

string readUntil(ref StringStream s, char until)
{
	auto start = s.s.ptr + s.position;
	auto p = start;
	while (*p != until) p++;
	auto len = p-start;
	s.position += len + 1;
	return start[0..len];
}

unittest
{
	enum xmlText =
		`<?xml version="1.0" encoding="UTF-8"?>` ~
		`<quotes>` ~
			`<quote author="Alan Perlis">` ~
				`When someone says, &quot;I want a programming language in which I need only say what I want done,&quot; give him a lollipop.` ~
			`</quote>` ~
		`</quotes>`;
	auto doc = new XmlDocument(xmlText);
	assert(doc.toString() == xmlText);
}

unittest
{
	enum xmlText =
		`<?xml version="1.0" encoding="UTF-8"?>` ~
		`<ns:quotes>` ~
			`<ns2:quote ns2:author="Alan Perlis">` ~
				`When someone says, &quot;I want a programming language in which I need only say what I want done,&quot; give him a lollipop.` ~
			`</ns2:quote>` ~
		`</ns:quotes>`;
	auto doc = new XmlDocument(xmlText);
	assert(doc.findChild("quotes"));
	assert(doc.findChild("ns:quotes"));
	assert(doc.findChild("quotes").namespace == "ns");
	assert(doc.toString() == xmlText, doc.toString());
}

const dchar[string] entities;
/*const*/ string[dchar] entityNames;
shared static this()
{
	entities =
	[
		"quot" : '\&quot;',
		"amp" : '\&amp;',
		"lt" : '\&lt;',
		"gt" : '\&gt;',

		"OElig" : '\&OElig;',
		"oelig" : '\&oelig;',
		"Scaron" : '\&Scaron;',
		"scaron" : '\&scaron;',
		"Yuml" : '\&Yuml;',
		"circ" : '\&circ;',
		"tilde" : '\&tilde;',
		"ensp" : '\&ensp;',
		"emsp" : '\&emsp;',
		"thinsp" : '\&thinsp;',
		"zwnj" : '\&zwnj;',
		"zwj" : '\&zwj;',
		"lrm" : '\&lrm;',
		"rlm" : '\&rlm;',
		"ndash" : '\&ndash;',
		"mdash" : '\&mdash;',
		"lsquo" : '\&lsquo;',
		"rsquo" : '\&rsquo;',
		"sbquo" : '\&sbquo;',
		"ldquo" : '\&ldquo;',
		"rdquo" : '\&rdquo;',
		"bdquo" : '\&bdquo;',
		"dagger" : '\&dagger;',
		"Dagger" : '\&Dagger;',
		"permil" : '\&permil;',
		"lsaquo" : '\&lsaquo;',
		"rsaquo" : '\&rsaquo;',
		"euro" : '\&euro;',

		"nbsp" : '\&nbsp;',
		"iexcl" : '\&iexcl;',
		"cent" : '\&cent;',
		"pound" : '\&pound;',
		"curren" : '\&curren;',
		"yen" : '\&yen;',
		"brvbar" : '\&brvbar;',
		"sect" : '\&sect;',
		"uml" : '\&uml;',
		"copy" : '\&copy;',
		"ordf" : '\&ordf;',
		"laquo" : '\&laquo;',
		"not" : '\&not;',
		"shy" : '\&shy;',
		"reg" : '\&reg;',
		"macr" : '\&macr;',
		"deg" : '\&deg;',
		"plusmn" : '\&plusmn;',
		"sup2" : '\&sup2;',
		"sup3" : '\&sup3;',
		"acute" : '\&acute;',
		"micro" : '\&micro;',
		"para" : '\&para;',
		"middot" : '\&middot;',
		"cedil" : '\&cedil;',
		"sup1" : '\&sup1;',
		"ordm" : '\&ordm;',
		"raquo" : '\&raquo;',
		"frac14" : '\&frac14;',
		"frac12" : '\&frac12;',
		"frac34" : '\&frac34;',
		"iquest" : '\&iquest;',
		"Agrave" : '\&Agrave;',
		"Aacute" : '\&Aacute;',
		"Acirc" : '\&Acirc;',
		"Atilde" : '\&Atilde;',
		"Auml" : '\&Auml;',
		"Aring" : '\&Aring;',
		"AElig" : '\&AElig;',
		"Ccedil" : '\&Ccedil;',
		"Egrave" : '\&Egrave;',
		"Eacute" : '\&Eacute;',
		"Ecirc" : '\&Ecirc;',
		"Euml" : '\&Euml;',
		"Igrave" : '\&Igrave;',
		"Iacute" : '\&Iacute;',
		"Icirc" : '\&Icirc;',
		"Iuml" : '\&Iuml;',
		"ETH" : '\&ETH;',
		"Ntilde" : '\&Ntilde;',
		"Ograve" : '\&Ograve;',
		"Oacute" : '\&Oacute;',
		"Ocirc" : '\&Ocirc;',
		"Otilde" : '\&Otilde;',
		"Ouml" : '\&Ouml;',
		"times" : '\&times;',
		"Oslash" : '\&Oslash;',
		"Ugrave" : '\&Ugrave;',
		"Uacute" : '\&Uacute;',
		"Ucirc" : '\&Ucirc;',
		"Uuml" : '\&Uuml;',
		"Yacute" : '\&Yacute;',
		"THORN" : '\&THORN;',
		"szlig" : '\&szlig;',
		"agrave" : '\&agrave;',
		"aacute" : '\&aacute;',
		"acirc" : '\&acirc;',
		"atilde" : '\&atilde;',
		"auml" : '\&auml;',
		"aring" : '\&aring;',
		"aelig" : '\&aelig;',
		"ccedil" : '\&ccedil;',
		"egrave" : '\&egrave;',
		"eacute" : '\&eacute;',
		"ecirc" : '\&ecirc;',
		"euml" : '\&euml;',
		"igrave" : '\&igrave;',
		"iacute" : '\&iacute;',
		"icirc" : '\&icirc;',
		"iuml" : '\&iuml;',
		"eth" : '\&eth;',
		"ntilde" : '\&ntilde;',
		"ograve" : '\&ograve;',
		"oacute" : '\&oacute;',
		"ocirc" : '\&ocirc;',
		"otilde" : '\&otilde;',
		"ouml" : '\&ouml;',
		"divide" : '\&divide;',
		"oslash" : '\&oslash;',
		"ugrave" : '\&ugrave;',
		"uacute" : '\&uacute;',
		"ucirc" : '\&ucirc;',
		"uuml" : '\&uuml;',
		"yacute" : '\&yacute;',
		"thorn" : '\&thorn;',
		"yuml" : '\&yuml;',

		"fnof" : '\&fnof;',
		"Alpha" : '\&Alpha;',
		"Beta" : '\&Beta;',
		"Gamma" : '\&Gamma;',
		"Delta" : '\&Delta;',
		"Epsilon" : '\&Epsilon;',
		"Zeta" : '\&Zeta;',
		"Eta" : '\&Eta;',
		"Theta" : '\&Theta;',
		"Iota" : '\&Iota;',
		"Kappa" : '\&Kappa;',
		"Lambda" : '\&Lambda;',
		"Mu" : '\&Mu;',
		"Nu" : '\&Nu;',
		"Xi" : '\&Xi;',
		"Omicron" : '\&Omicron;',
		"Pi" : '\&Pi;',
		"Rho" : '\&Rho;',
		"Sigma" : '\&Sigma;',
		"Tau" : '\&Tau;',
		"Upsilon" : '\&Upsilon;',
		"Phi" : '\&Phi;',
		"Chi" : '\&Chi;',
		"Psi" : '\&Psi;',
		"Omega" : '\&Omega;',
		"alpha" : '\&alpha;',
		"beta" : '\&beta;',
		"gamma" : '\&gamma;',
		"delta" : '\&delta;',
		"epsilon" : '\&epsilon;',
		"zeta" : '\&zeta;',
		"eta" : '\&eta;',
		"theta" : '\&theta;',
		"iota" : '\&iota;',
		"kappa" : '\&kappa;',
		"lambda" : '\&lambda;',
		"mu" : '\&mu;',
		"nu" : '\&nu;',
		"xi" : '\&xi;',
		"omicron" : '\&omicron;',
		"pi" : '\&pi;',
		"rho" : '\&rho;',
		"sigmaf" : '\&sigmaf;',
		"sigma" : '\&sigma;',
		"tau" : '\&tau;',
		"upsilon" : '\&upsilon;',
		"phi" : '\&phi;',
		"chi" : '\&chi;',
		"psi" : '\&psi;',
		"omega" : '\&omega;',
		"thetasym" : '\&thetasym;',
		"upsih" : '\&upsih;',
		"piv" : '\&piv;',
		"bull" : '\&bull;',
		"hellip" : '\&hellip;',
		"prime" : '\&prime;',
		"Prime" : '\&Prime;',
		"oline" : '\&oline;',
		"frasl" : '\&frasl;',
		"weierp" : '\&weierp;',
		"image" : '\&image;',
		"real" : '\&real;',
		"trade" : '\&trade;',
		"alefsym" : '\&alefsym;',
		"larr" : '\&larr;',
		"uarr" : '\&uarr;',
		"rarr" : '\&rarr;',
		"darr" : '\&darr;',
		"harr" : '\&harr;',
		"crarr" : '\&crarr;',
		"lArr" : '\&lArr;',
		"uArr" : '\&uArr;',
		"rArr" : '\&rArr;',
		"dArr" : '\&dArr;',
		"hArr" : '\&hArr;',
		"forall" : '\&forall;',
		"part" : '\&part;',
		"exist" : '\&exist;',
		"empty" : '\&empty;',
		"nabla" : '\&nabla;',
		"isin" : '\&isin;',
		"notin" : '\&notin;',
		"ni" : '\&ni;',
		"prod" : '\&prod;',
		"sum" : '\&sum;',
		"minus" : '\&minus;',
		"lowast" : '\&lowast;',
		"radic" : '\&radic;',
		"prop" : '\&prop;',
		"infin" : '\&infin;',
		"ang" : '\&ang;',
		"and" : '\&and;',
		"or" : '\&or;',
		"cap" : '\&cap;',
		"cup" : '\&cup;',
		"int" : '\&int;',
		"there4" : '\&there4;',
		"sim" : '\&sim;',
		"cong" : '\&cong;',
		"asymp" : '\&asymp;',
		"ne" : '\&ne;',
		"equiv" : '\&equiv;',
		"le" : '\&le;',
		"ge" : '\&ge;',
		"sub" : '\&sub;',
		"sup" : '\&sup;',
		"nsub" : '\&nsub;',
		"sube" : '\&sube;',
		"supe" : '\&supe;',
		"oplus" : '\&oplus;',
		"otimes" : '\&otimes;',
		"perp" : '\&perp;',
		"sdot" : '\&sdot;',
		"lceil" : '\&lceil;',
		"rceil" : '\&rceil;',
		"lfloor" : '\&lfloor;',
		"rfloor" : '\&rfloor;',
		"loz" : '\&loz;',
		"spades" : '\&spades;',
		"clubs" : '\&clubs;',
		"hearts" : '\&hearts;',
		"diams" : '\&diams;',
		"lang" : '\&lang;',
		"rang" : '\&rang;',

		"apos"  : '\''
	];
	foreach (name, c; entities)
		entityNames[c] = name;
}

import core.stdc.stdio;
import std.utf;
import ae.utils.textout;

public string encodeEntities(string str)
{
	foreach (i, c; str)
		if (c=='<' || c=='>' || c=='"' || c=='\'' || c=='&')
		{
			StringBuilder sb;
			sb.preallocate(str.length * 11 / 10);
			sb.put(str[0..i]);
			sb.putEncodedEntities(str[i..$]);
			return sb.get();
		}
	return str;
}

public void putEncodedEntities(Sink, S)(ref Sink sink, S str)
{
	size_t start = 0;
	foreach (i, c; str)
		if (c=='<' || c=='>' || c=='"' || c=='\'' || c=='&')
		{
			sink.put(str[start..i], '&', entityNames[c], ';');
			start = i+1;
		}
	sink.put(str[start..$]);
}

public string encodeAllEntities(string str)
{
	// TODO: optimize
	foreach_reverse (i, dchar c; str)
	{
		auto name = c in entityNames;
		if (name)
			str = str[0..i] ~ '&' ~ *name ~ ';' ~ str[i+stride(str,i)..$];
	}
	return str;
}

import ae.utils.text;
import std.conv;

public string decodeEntities(string str)
{
	auto fragments = str.fastSplit('&');
	if (fragments.length <= 1)
		return str;

	auto interleaved = new string[fragments.length*2 - 1];
	auto buffers = new char[4][fragments.length-1];
	interleaved[0] = fragments[0];

	foreach (n, fragment; fragments[1..$])
	{
		auto p = fragment.indexOf(';');
		enforce!XmlParseException(p>0, "Invalid entity (unescaped ampersand?)");

		dchar c;
		if (fragment[0]=='#')
		{
			if (fragment[1]=='x')
				c = fromHex!uint(fragment[2..p]);
			else
				c = to!uint(fragment[1..p]);
		}
		else
		{
			auto pentity = fragment[0..p] in entities;
			enforce!XmlParseException(pentity, "Unknown entity: " ~ fragment[0..p]);
			c = *pentity;
		}

		interleaved[1+n*2] = cast(string) buffers[n][0..std.utf.encode(buffers[n], c)];
		interleaved[2+n*2] = fragment[p+1..$];
	}

	return interleaved.join();
}

deprecated alias decodeEntities convertEntities;

unittest
{
	assert(encodeEntities(`The <Smith & Wesson> "lock'n'load"`) == `The &lt;Smith &amp; Wesson&gt; &quot;lock&apos;n&apos;load&quot;`);
	assert(encodeAllEntities("©,€") == "&copy;,&euro;");
	assert(decodeEntities("&copy;,&euro;") == "©,€");
}
