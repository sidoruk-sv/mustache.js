###
 mustache.js - Logic-less {{mustache}} templates with JavaScript
 http://github.com/janl/mustache.js
###

#global define: false
factory = (mustache) ->
  Object_toString = Object.prototype.toString

  isArrayOld = (object) ->
    Object_toString.call(object) == '[object Array]'

  isArray = Array.isArray or isArrayOld

  isFunction = (object) ->
    typeof object == 'function'

  escapeRegExp = (string) ->
    string.replace(/[\-\[\]{}()*+?.,\\\^$|#\s]/g, "\\$&")

  RegExp_test = RegExp.prototype.test

  testRegExp = (re, string) ->
    RegExp_test.call(re, string)

  nonSpaceRe = /\S/

  isWhitespace = (string) ->
    !testRegExp(nonSpaceRe, string)

  entityMap =
    "&": "&amp;"
    "<": "&lt;"
    ">": "&gt;"
    '"': '&quot;'
    "'": '&#39;'
    "/": '&#x2F;'


  escapeHtml = (string) ->
    String(string).replace  /[&<>"'\/]/g, (s) ->
      entityMap[s]

  whiteRe = /\s*/;
  spaceRe = /\s+/;
  equalsRe = /\s*=/;
  curlyRe = /\s*\}/;
  tagRe = /#|\^|\/|>|\{|&|=|!/;


  parseTemplate = (template, tags) ->
    return [] if !template

    sections = [];
    tokens = [];
    spaces = [];
    hasTag = false;
    nonSpace = false;

    stripSpace = ->
      if (hasTag and !nonSpace)
        while (spaces.length)
          delete tokens[spaces.pop()]
      else
        spaces = [];

      hasTag = false;
      nonSpace = false;



    compileTags = (tags) ->
      tags = tags.split(spaceRe, 2) if (typeof tags == 'string')
      throw new Error('Invalid tags: ' + tags) if (!isArray(tags) or tags.length != 2)
      openingTagRe = new RegExp(escapeRegExp(tags[0]) + '\\s*')
      closingTagRe = new RegExp('\\s*' + escapeRegExp(tags[1]))
      closingCurlyRe = new RegExp('\\s*' + escapeRegExp('}' + tags[1]))


    compileTags(tags or mustache.tags)

    scanner = new Scanner(template)

    until !scanner.eos()
      start = scanner.pos
      value = scanner.scanUntil(openingTagRe)

      ###
      value?
        for (i = 0, valueLength = value.length; i < valueLength; ++i)
          chr = value.charAt(i)

          if (isWhitespace(chr))
            spaces.push(tokens.length);
          else
            nonSpace = true;


          tokens.push([ 'text', chr, start, start + 1 ])
          start += 1

          stripSpace() if (chr == '\n')
      ###


      break if (!scanner.scan(openingTagRe))

      hasTag = true

      type = scanner.scan(tagRe) or 'name'
      scanner.scan(whiteRe);


      if (type == '=')
        value = scanner.scanUntil(equalsRe)
        scanner.scan(equalsRe)
        scanner.scanUntil(closingTagRe)
      else if (type == '{')
        value = scanner.scanUntil(closingCurlyRe)
        scanner.scan(curlyRe)
        scanner.scanUntil(closingTagRe)
        type = '&'
      else
        value = scanner.scanUntil(closingTagRe)

      throw new Error('Unclosed tag at ' + scanner.pos) if !scanner.scan(closingTagRe)

      token = [ type, value, start, scanner.pos ]
      tokens.push(token)

      if (type == '#' or type == '^')
        sections.push(token)
      else if (type == '/')
        openSection = sections.pop()
        throw new Error('Unopened section "' + value + '" at ' + start) if !openSection
        throw new Error('Unclosed section "' + openSection[1] + '" at ' + start) if (openSection[1] != value)
      else if (type == 'name' or type == '{' or type == '&')
        nonSpace = true
      else if (type == '=')
        compileTags(value)

    openSection = sections.pop();

    throw new Error('Unclosed section "' + openSection[1] + '" at ' + scanner.pos) if openSection

    return nestTokens(squashTokens(tokens))

  squashTokens = (tokens) ->
    squashedTokens = []

    ###
    for (var i = 0, numTokens = tokens.length; i < numTokens; ++i) {
      token = tokens[i]

      token?
        if (token[0] == 'text' and lastToken and lastToken[0] == 'text')
          lastToken[1] += token[1]
          lastToken[3] = token[3]
        else
          squashedTokens.push(token)
          lastToken = token
    }
    ###

    return  squashedTokens


  nestTokens = (tokens) ->

    nestedTokens = []
    sections = []

    ###
    for (i = 0, numTokens = tokens.length; i < numTokens; ++i) {
      token = tokens[i];

      switch token[0]
        when '#' then
        when '^' then
          collector.push(token);
          sections.push(token);
          collector = token[4] = [];
          break;
        when '/' then
          section = sections.pop();
          section[5] = token[2];
          collector = sections.length > 0 ? sections[sections.length - 1][4] : nestedTokens;
          break;
        else:
          collector.push(token);
    }
    ###
    return nestedTokens


  Scanner = (string) ->
    this.string = string
    this.tail = string
    this.pos = 0


  Scanner.prototype.eos = ->
    this.tail == ""


  Scanner.prototype.scan = (re) ->
    match = this.tail.match(re)

    return '' if (!match or match.index != 0)

    string = match[0]

    this.tail = this.tail.substring(string.length)
    this.pos += string.length

    return string


  Scanner.prototype.scanUntil = (re) ->
    index = this.tail.search(re)

    ###
    switch index
      when -1 then
        match = this.tail
        this.tail = ""
      when 0 then match = ""
      else
        match = this.tail.substring(0, index)
        this.tail = this.tail.substring(index)
    ###

    this.pos += match.length
    return match


  Context = (view, parentContext) ->
    this.view = if view == null then {} else view
    this.cache = {'.': this.view}
    this.parent = parentContext


  Context.prototype.push = (view) ->
    new Context(view, this)

  Context.prototype.lookup = (name) ->
    cache = this.cache

    if (name in cache)
      value = cache[name];
    else
      ###
      context = this, names, index

      while (context) {

        if (name.indexOf('.') > 0)
          value = context.view
          names = name.split('.')
          index = 0
          value = value[names[index++]] while (value != null and index < names.length)
        else
          value = context.view[name]

        break if (value != null)

        context = context.parent
      }
      ###

      cache[name] = value

    value = value.call(this.view) if isFunction(value)

    return value


  Writer = ->
    this.cache = {}


  Writer.prototype.clearCache = ->
    this.cache = {}


  Writer.prototype.parse = (template, tags) ->
    cache = this.cache;
    tokens = cache[template];

    tokens = cache[template] = parseTemplate(template, tags) if (tokens == null)

    return tokens;


  Writer.prototype.render = (template, view, partials) ->
    tokens = this.parse(template)
    context = if (view instanceof Context) then view else new Context(view)
    render this.renderTokens(tokens, context, partials, template)

  Writer.prototype.renderTokens = (tokens, context, partials, originalTemplate) ->
    buffer = ''
    self = this

    subRender = (template) ->
      self.render(template, context, partials)

      ###
      for (var i = 0, numTokens = tokens.length; i < numTokens; ++i) {
        token = tokens[i]

        switch token[0]
          when '#' then
            value = context.lookup(token[1])

            continue if !value

            if (isArray(value))
              for (var j = 0, valueLength = value.length; j < valueLength; ++j) {
                  buffer += this.renderTokens(token[4], context.push(value[j]), partials, originalTemplate);
              }
            else if (typeof value == 'object' or typeof value == 'string')
                buffer += this.renderTokens(token[4], context.push(value), partials, originalTemplate)
            else if (isFunction(value))

              throw new Error('Cannot use higher-order sections without the original template') if (typeof originalTemplate != 'string')

              value = value.call(context.view, originalTemplate.slice(token[3], token[5]), subRender)


              buffer += valueaw if (value != null)

            else
              buffer += this.renderTokens(token[4], context, partials, originalTemplate)

          when '^' then
            value = context.lookup(token[1])

            buffer += this.renderTokens(token[4], context, partials, originalTemplate) if (!value or (isArray(value) and value.length == 0))

          when '>' then
            continue if (!partials)

            value = isFunction(partials) ? partials(token[1]) : partials[token[1]];

            buffer += this.renderTokens(this.parse(value), context, partials, value) if (value != null)

          when '&' then

            value = context.lookup(token[1])
            buffer += value if (value != null)

          when 'name' then
            value = context.lookup(token[1]);
            buffer += mustache.escape(value) if (value != null)

          when 'text' then buffer += token[1]
      }
      ###
    return buffer

  mustache.name = "mustache.js"
  mustache.version = "0.8.1"
  mustache.tags = ["{{", "}}"]

  defaultWriter = new Writer()

  mustache.clearCache = ->
    defaultWriter.clearCache()

  mustache.parse = (template, tags) ->
    defaultWriter.parse(template, tags)


  mustache.render = (template, view, partials) ->
    defaultWriter.render(template, view, partials)

  mustache.to_html = (template, view, partials, send) ->
    result = mustache.render(template, view, partials);

    if (isFunction(send))
      send(result)
    else
      return result

  mustache.escape = escapeHtml

  mustache.Scanner = Scanner
  mustache.Context = Context
  mustache.Writer = Writer



do (global = this, factory) ->
  if typeof exports == "object" and exports
      factory(exports)
  else if typeof define == "function" and define.amd
      define(['exports'], factory)
  else
      factory(global.Mustache = {})
