###!
 mustache.js - Logic-less {{mustache}} templates with JavaScript
 http://github.com/janl/mustache.js
###

###
global define: false
###

factory = (mustache) ->

  Object_toString = Object::toString

  isArrayOld = (object) ->
    Object_toString.call(object) is '[object Array]'

  isArray = Array.isArray or isArrayOld

  isFunction = (object) ->
    typeof object is 'function'

  escapeRegExp = (string) ->
    string.replace(/[\-\[\]{}()*+?.,\\\^$|#\s]/g, '\\$&')

  #! Workaround for https://issues.apache.org/jira/browse/COUCHDB-577
  #! See https://github.com/janl/mustache.js/issues/189
  RegExp_test = RegExp::test

  testRegExp = (re, string) ->
    RegExp_test.call(re, string)

  nonSpaceRe = /\S/

  isWhitespace = (string) ->
    not testRegExp(nonSpaceRe, string)

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


  ###*
     * Breaks up the given `template` string into a tree of tokens. If the `tags`
     * argument is given here it must be an array with two string values: the
     * opening and closing tags used in the template (e.g. [ "<%", "%>" ]). Of
     * course, the default is to use mustaches (i.e. mustache.tags).
     *
     * A token is an array with at least 4 elements. The first element is the
     * mustache symbol that was used inside the tag, e.g. "#" or "&". If the tag
     * did not contain a symbol (i.e. {{myValue}}) this element is "name". For
     * all text that appears outside a symbol this element is "text".
     *
     * The second element of a token is its "value". For mustache tags this is
     * whatever else was inside the tag besides the opening symbol. For text tokens
     * this is the text itself.
     *
     * The third and fourth elements of the token are the start and end indices,
     * respectively, of the token in the original template.
     *
     * Tokens that are the root node of a subtree contain two more elements: 1) an
     * array of tokens in the subtree and 2) the index in the original template at
     * which the closing tag for that section begins.
  ###
  parseTemplate = (template, tags) ->
    return [] if not template

    sections = []     # Stack to hold section tokens
    tokens = []       # Buffer to hold the tokens
    spaces = []       # Indices of whitespace tokens on the current line
    hasTag = false    # Is there a {{tag}} on the current line?
    nonSpace = false  # Is there a non-space char on the current line?

    # Strips all whitespace tokens array for the current line
    # if there was a {{#tag}} on it and otherwise only space.

    stripSpace = ->
      if hasTag and not nonSpace
        while spaces.length
          delete tokens[spaces.pop()]
      else
        spaces = []

      hasTag = false
      nonSpace = false

    closingCurlyRe = undefined
    closingTagRe = undefined
    openingTagRe = undefined
    compileTags = (tags) ->
      tags = tags.split(spaceRe, 2) if typeof tags is 'string'
      throw new Error("Invalid tags: #{tags}") if not isArray(tags) or tags.length isnt 2
      openingTagRe = new RegExp("#{escapeRegExp(tags[0])}\\s*")
      closingTagRe = new RegExp("\\s*#{escapeRegExp(tags[1])}")
      closingCurlyRe = new RegExp("\\s*#{escapeRegExp('}' + tags[1])}")

    compileTags(tags or mustache.tags)

    scanner = new Scanner(template)

    until scanner.eos()
      start = scanner.pos

      # Match any text between tags.
      value = scanner.scanUntil(openingTagRe)

      if value
        for i in value
          chr = value.charAt(i)

          if isWhitespace(chr)
            spaces.push(tokens.length)
          else
            nonSpace = true

          tokens.push([ 'text', chr, start, start + 1 ])
          start += 1

          # Check for whitespace on the current line.
          stripSpace() if chr is '\n'

      # Match the opening tag.
      break if not scanner.scan(openingTagRe)

      hasTag = true

      # Get the tag type.
      type = scanner.scan(tagRe) or 'name'
      scanner.scan(whiteRe)

      # Get the tag value.
      if type is '='
        value = scanner.scanUntil(equalsRe)
        scanner.scan(equalsRe)
        scanner.scanUntil(closingTagRe)
      else if type is '{'
        value = scanner.scanUntil(closingCurlyRe)
        scanner.scan(curlyRe)
        scanner.scanUntil(closingTagRe)
        type = '&'
      else
        value = scanner.scanUntil(closingTagRe)

      # Match the closing tag.
      throw new Error("Unclosed tag at #{scanner.pos}") unless scanner.scan(closingTagRe)

      token = [ type, value, start, scanner.pos ]
      tokens.push(token)

      if type in ['#', '^']
        sections.push(token)
      else if type is '/'
        # Check section nesting.
        openSection = sections.pop()
        throw new Error("Unopened section \"#{value}\" at #{start}") if not openSection
        throw new Error("Unclosed section \"#{openSection[1]}\" at #{start}") if openSection[1] isnt value
      else if type in ['name', '{', '&']
        nonSpace = true
      else if type is '='
        # Set the tags for the next time around.
        compileTags(value)

    # Make sure there are no open sections when we're done.
    openSection = sections.pop()

    throw new Error("Unclosed section \"#{openSection[1]}\" at #{scanner.pos}") if openSection

    return nestTokens(squashTokens(tokens))

  ###*
    * Combines the values of consecutive text tokens in the given `tokens` array
    * to a single token.
  ###
  squashTokens = (tokens) ->
    squashedTokens = []

    # alarm! unesed token
    for token, i in tokens
      if token
        if token[0] is 'text' and lastToken and lastToken[0] is 'text'
          lastToken[1] += token[1]
          lastToken[3] = token[3]
        else
          squashedTokens.push(token)
          lastToken = token

    return  squashedTokens

  ###*
     * Forms the given array of `tokens` into a nested tree structure where
     * tokens that represent a section have two additional items: 1) an array of
     * all tokens that appear in that section and 2) the index in the original
     * template that represents the end of that section.
  ###
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


  ###*
     * A simple string scanner that is used by the template parser to find
     * tokens in template strings.
  ###
  Scanner = (@string) ->
    @tail = string
    @pos = 0
    return

  ###*
     * Returns `true` if the tail is empty (end of string).
  ###
  Scanner::eos = ->
    @tail is ''

  ###*
     * Tries to match the given regular expression at the current position.
     * Returns the matched text if it can match, the empty string otherwise.
  ###
  Scanner::scan = (re) ->
    match = @tail.match(re)

    return '' if not match or match.index isnt 0

    string = match[0]

    @tail = @tail.slice(string.length)
    @pos += string.length

    return string

  ###*
     * Skips all text until the given regular expression can be matched. Returns
     * the skipped string, which is the entire tail if no match can be made.
  ###
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

  ###*
     * Represents a rendering context by wrapping a view object and
     * maintaining a reference to the parent context.
  ###
  Context = (view, parentContext) ->
    @view = view ? {}
    @cache = {'.': @view}
    @parent = parentContext


  ###*
     * Creates a new context using the given view with this context
     * as the parent.
  ###
  Context::push = (view) ->
    new Context(view, this)

  ###*
     * Returns the value of the given name in this context, traversing
     * up the context hierarchy if the value is absent in this context's view.
  ###
  Context::lookup = (name) ->
    cache = @cache

    if name in cache
      value = cache[name]
    else
      context = this
      names =  undefined
      index = undefined

      while context
        if name.indexOf('.') > 0
          value = context.view
          names = name.split('.')
          index = 0
          value = value[names[index++]] while value? and index < names.length
        else
          value = context.view[name]

        break if value?

        context = context.parent

      cache[name] = value

    value = value.call(@view) if isFunction(value)

    return value

  ###*
     * A Writer knows how to take a stream of tokens and render them to a
     * string, given a context. It also maintains a cache of templates to
     * avoid the need to parse the same template twice.
  ###
  Writer = ->
    @cache = {}

  ###*
     * Clears all cached templates in this writer.
  ###
  Writer::clearCache = ->
    @cache = {}


  ###*
    * Parses and caches the given `template` and returns the array of tokens
    * that is generated from the parse.
  ###
  Writer::parse = (template, tags) ->
    cache = @cache
    tokens = cache[template]

    tokens = cache[template] = parseTemplate(template, tags) unless tokens?

    return tokens


  ###*
     * High-level method that is used to render the given `template` with
     * the given `view`.
     *
     * The optional `partials` argument may be an object that contains the
     * names and templates of partials that are used in the template. It may
     * also be a function that is used to load partial templates on the fly
     * that takes a single argument: the name of the partial.
  ###
  Writer::render = (template, view, partials) ->
    tokens = @parse(template)
    context = if view instanceof Context then view else new Context(view)
    return @renderTokens(tokens, context, partials, template)

  ###*
     * Low-level method that renders the given array of `tokens` using
     * the given `context` and `partials`.
     *
     * Note: The `originalTemplate` is only ever used to extract the portion
     * of the original template that was contained in a higher-order section.
     * If the template doesn't use higher-order sections, this argument may
     * be omitted.
  ###
  Writer::renderTokens = (tokens, context, partials, originalTemplate) ->
    buffer = ''

    # This function is used to render an arbitrary template
    # in the current context by higher-order sections.

    self = this
    subRender = (template) ->
      self.render(template, context, partials)


      for token, i in tokens
        switch token[0]
          when '#'
            value = context.lookup(token[1])

            continue if not value

            if isArray(value)
              # alarm! unesed k
              for j, k in value
                  buffer += @renderTokens(token[4], context.push(value[j]), partials, originalTemplate)

            else if typeof value in ['object', 'string']
                buffer += @renderTokens(token[4], context.push(value), partials, originalTemplate)

            else if isFunction(value)
              throw new Error('Cannot use higher-order sections without the original template') if typeof originalTemplate isnt 'string'
              # Extract the portion of the original template that the section contains.
              value = value.call(context.view, originalTemplate.slice(token[3], token[5]), subRender)
              buffer += value if value?

            else
              buffer += @renderTokens(token[4], context, partials, originalTemplate)

          when '^'
            value = context.lookup(token[1])
            # Use JavaScript's definition of falsy. Include empty arrays.
            # See https://github.com/janl/mustache.js/issues/186

            buffer += @renderTokens(token[4], context, partials, originalTemplate) if not value or (isArray(value) and value.length is 0)

          when '>'
            continue if not partials

            value = if isFunction(partials) then partials(token[1]) else partials[token[1]]

            buffer += @renderTokens(@parse(value), context, partials, value) if value?

          when '&'
            value = context.lookup(token[1])
            buffer += value if value?

          when 'name'
            value = context.lookup(token[1])
            buffer += mustache.escape(value) if value?

          when 'text'
             buffer += token[1]

    return buffer

  mustache.name = 'mustache.js'
  mustache.version = '0.8.1'
  mustache.tags = ['{{', '}}']

  # All high-level mustache.* functions use this writer.
  defaultWriter = new Writer()

  ###*
     * Clears all cached templates in the default writer.
  ###
  mustache.clearCache = ->
    defaultWriter.clearCache()

  ###*
     * Parses and caches the given template in the default writer and returns the
     * array of tokens it contains. Doing this ahead of time avoids the need to
     * parse templates on the fly as they are rendered.
  ###
  mustache.parse = (template, tags) ->
    defaultWriter.parse(template, tags)

  ###*
     * Renders the `template` with the given `view` and `partials` using the
     * default writer.
  ###
  mustache.render = (template, view, partials) ->
    defaultWriter.render(template, view, partials)

  # This is here for backwards compatibility with 0.4.x.
  mustache.to_html = (template, view, partials, send) ->
    result = mustache.render(template, view, partials)
    if isFunction(send) then send(result) else result

  # Export the escaping function so that the user may override it.
  # See https://github.com/janl/mustache.js/issues/244
  mustache.escape = escapeHtml

  # Export these mainly for testing, but also for advanced usage.
  mustache.Scanner = Scanner
  mustache.Context = Context
  mustache.Writer = Writer



do (global = this, factory) ->
  if typeof exports is 'object' and exports
      factory(exports) # CommonJS
  else if typeof define is 'function' and define.amd
      define(['exports'], factory) # AMD
  else
      factory(global.Mustache = {}) # <script>
