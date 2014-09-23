###
 mustache.js - Logic-less {{mustache}} templates with JavaScript
 http://github.com/janl/mustache.js
###

#global define: false
factory = (mustache) ->
  Object_toString = Object::toString

  isArrayOld = (object) ->
    Object_toString.call(object) is '[object Array]'

  isArray = Array.isArray or isArrayOld

  isFunction = (object) ->
    typeof object is 'function'

  escapeRegExp = (string) ->
    string.replace(/[\-\[\]{}()*+?.,\\\^$|#\s]/g, '\\$&')

  RegExp_test = RegExp::test

  testRegExp = (re, string) ->
    RegExp_test.call(re, string)

  nonSpaceRe = /\S/

  isWhitespace = (string) ->
    !testRegExp(nonSpaceRe, string)

  entityMap =
    '&': '&amp;'
    '<': '&lt;'
    '>': '&gt;'
    '\"': '&quot;'
    '\'': '&#39;'
    '/': '&#x2F;'


  escapeHtml = (string) ->
    String(string).replace  /[&<>"'\/]/g, (s) ->
      entityMap[s]

  whiteRe = /\s*/
  spaceRe = /\s+/
  equalsRe = /\s*=/
  curlyRe = /\s*\}/
  tagRe = /#|\^|\/|>|\{|&|=|!/


  parseTemplate = (template, tags) ->
    return [] if !template

    sections = []
    tokens = []
    spaces = []
    hasTag = false
    nonSpace = false

    stripSpace = ->
      if (hasTag and !nonSpace)
        while (spaces.length)
          delete tokens[spaces.pop()]
      else
        spaces = []

      hasTag = false
      nonSpace = false



    compileTags = (tags) ->
      tags = tags.split(spaceRe, 2) if (typeof tags is 'string')
      throw new Error('Invalid tags: ' + tags) if (!isArray(tags) or tags.length isnt 2)
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
            spaces.push(tokens.length)
          else
            nonSpace = true


          tokens.push([ 'text', chr, start, start + 1 ])
          start += 1

          stripSpace() if (chr is '\n')
      ###


      break if !scanner.scan(openingTagRe)

      hasTag = true

      type = scanner.scan(tagRe) or 'name'
      scanner.scan(whiteRe)


      if (type is '=')
        value = scanner.scanUntil(equalsRe)
        scanner.scan(equalsRe)
        scanner.scanUntil(closingTagRe)
      else if (type is '{')
        value = scanner.scanUntil(closingCurlyRe)
        scanner.scan(curlyRe)
        scanner.scanUntil(closingTagRe)
        type = '&'
      else
        value = scanner.scanUntil(closingTagRe)

      throw new Error('Unclosed tag at ' + scanner.pos) if !scanner.scan(closingTagRe)

      token = [ type, value, start, scanner.pos ]
      tokens.push(token)

      if (type is '#' or type is '^')
        sections.push(token)
      else if (type is '/')
        openSection = sections.pop()
        throw new Error('Unopened section "' + value + '" at ' + start) if !openSection
        throw new Error('Unclosed section "' + openSection[1] + '" at ' + start) if (openSection[1] isnt value)
      else if (type is 'name' or type is '{' or type is '&')
        nonSpace = true
      else if (type is '=')
        compileTags(value)

    openSection = sections.pop()

    throw new Error('Unclosed section "' + openSection[1] + '" at ' + scanner.pos) if openSection

    return nestTokens(squashTokens(tokens))

  squashTokens = (tokens) ->
    squashedTokens = []

    ###
    for (var i = 0, numTokens = tokens.length; i < numTokens ++i) {
      token = tokens[i]

      token?
        if (token[0] is 'text' and lastToken and lastToken[0] is 'text')
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
    collector = nestedTokens
    sections = []

    tokenParse = (token) ->
      switch token[0]
        when '#', '^'
          collector.push(token)
          sections.push(token)
          collector = token[4] = []
        when '/'
          section = sections.pop()
          section[5] = token[2]
          collector = if sections.length > 0 then sections[sections.length - 1][4] else nestedTokens
        else
          collector.push(token)

    tokenParse token for token in tokens

    return collector


  Scanner = (@string) ->
    @tail = string
    @pos = 0


  Scanner::eos = ->
    @tail is ''


  Scanner::scan = (re) ->
    match = @tail.match(re)

    return '' if (!match or match.index isnt 0)

    string = match[0]

    @tail = @tail.slice(string.length)
    @pos += string.length

    return string


  Scanner::scanUntil = (re) ->
    index = @tail.search(re)

    switch index
      when -1
        match = @tail
        @tail = ''
      when 0
        match = ''
      else
        match = @tail.slice(0, index)
        @tail = @tail.slice(index)

    @pos += match.length
    return match


  Context = (view, parentContext) ->
    @view = view ? {}
    @cache = {'.': @view}
    @parent = parentContext


  Context::push = (view) ->
    new Context(view, this)

  Context::lookup = (name) ->
    cache = @cache

    if (name in cache)
      value = cache[name]
    else
      ###
      context = this, names, index

      while (context) {

        if (name.indexOf('.') > 0)
          value = context.view
          names = name.split('.')
          index = 0
          value = value[names[index++]] while (value isnt null and index < names.length)
        else
          value = context.view[name]

        break if (value isnt null)

        context = context.parent
      }
      ###

      cache[name] = value

    value = value.call(@view) if isFunction(value)

    return value


  Writer = ->
    @cache = {}


  Writer::clearCache = ->
    @cache = {}


  Writer::parse = (template, tags) ->
    cache = @cache
    tokens = cache[template]

    tokens = cache[template] = parseTemplate(template, tags) if (tokens is null)

    return tokens


  Writer::render = (template, view, partials) ->
    tokens = @parse(template)
    context = if (view instanceof Context) then view else new Context(view)
    return @renderTokens(tokens, context, partials, template)

  Writer::renderTokens = (tokens, context, partials, originalTemplate) ->
    buffer = ''
    self = this

    subRender = (template) ->
      self.render(template, context, partials)

      ###
      for (var i = 0, numTokens = tokens.length; i < numTokens; ++i) {
        token = tokens[i]

        switch token[0]
          when '#'
            value = context.lookup(token[1])

            continue if !value

            if (isArray(value))
              for (var j = 0, valueLength = value.length; j < valueLength; ++j) {
                  buffer += @renderTokens(token[4], context.push(value[j]), partials, originalTemplate)
              }
            else if (typeof value is 'object' or typeof value is 'string')
                buffer += @renderTokens(token[4], context.push(value), partials, originalTemplate)
            else if (isFunction(value))

              throw new Error('Cannot use higher-order sections without the original template') if (typeof originalTemplate isnt 'string')

              value = value.call(context.view, originalTemplate.slice(token[3], token[5]), subRender)


              buffer += valueaw if (value isnt null)

            else
              buffer += @renderTokens(token[4], context, partials, originalTemplate)

          when '^'
            value = context.lookup(token[1])

            buffer += @renderTokens(token[4], context, partials, originalTemplate) if (!value or (isArray(value) and value.length is 0))

          when '>'
            continue if (!partials)

            value = isFunction(partials) ? partials(token[1]) : partials[token[1]]

            buffer += @renderTokens(@parse(value), context, partials, value) if (value isnt null)

          when '&'
            value = context.lookup(token[1])
            buffer += value if (value isnt null)

          when 'name'
            value = context.lookup(token[1])
            buffer += mustache.escape(value) if (value isnt null)

          when 'text'
             buffer += token[1]
      }
      ###
    return buffer

  mustache.name = 'mustache.js'
  mustache.version = '0.8.1'
  mustache.tags = ['{{', '}}']

  defaultWriter = new Writer()

  mustache.clearCache = ->
    defaultWriter.clearCache()

  mustache.parse = (template, tags) ->
    defaultWriter.parse(template, tags)


  mustache.render = (template, view, partials) ->
    defaultWriter.render(template, view, partials)

  mustache.to_html = (template, view, partials, send) ->
    result = mustache.render(template, view, partials)
    if isFunction(send) then send(result) else result

  mustache.escape = escapeHtml

  mustache.Scanner = Scanner
  mustache.Context = Context
  mustache.Writer = Writer



do (global = this, factory) ->
  if typeof exports is 'object' and exports
      factory(exports)
  else if typeof define is 'function' and define.amd
      define(['exports'], factory)
  else
      factory(global.Mustache = {})
