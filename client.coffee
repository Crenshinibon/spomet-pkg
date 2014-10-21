Deps.autorun () ->
    Meteor.subscribe 'common-terms'

Spomet.add = (docSpec, resultCb) ->
    Meteor.call 'spometAdd', docSpec, (error, result) ->
        if result?
            resultCb? result
    
Spomet.replace = (docSpec, refVersion, resultCb) ->
    if refVersion? and isNaN refVersion
         resultCb = refVersion
         refVersion = null
    
    Meteor.call 'spometReplace', docSpec, refVersion, (error, result) ->
        if result?
            resultCb? result
        
    
Spomet.remove = (docSpec, resultCb) ->
    Meteor.call 'spometRemove', docSpec, (error, result) ->
        if result?
            resultCb? result

class Spomet.Search
    
    constructor: () ->
        @collection = new Meteor.Collection null
        @subHandle = null
    
    set: (key, value) =>
        upd = {}
        upd[key] = value
        
        sel = {}
        sel[key] = {$exists: true}
        existing = @collection.findOne sel
        if existing?
            @collection.update {_id: existing._id}, upd
        else
            @collection.insert upd
              
    get: (key) =>
        sel = {}
        sel[key] = {$exists: true}
        existing = @collection.findOne sel
        if existing?
            existing[key]
        else
            null
    
    reSubscribe: () =>
        if @subHandle
            @subHandle.stop()
        
        search = @
        Deps.autorun () ->
            opts = 
                phrase: search.get 'current-phrase'
                sort: search.get 'search-sort'
                offset: search.get 'search-offset'
                limit: search.get 'search-limit'
                excludes: search.get 'excludes'
            search.subHandle = Meteor.subscribe 'search-results', opts
    
    setCurrentPhrase: (phrase) =>
        @set 'current-phrase', phrase
        @reSubscribe()
        
    getCurrentPhrase: () =>
        @get 'current-phrase'
    
    setSort: (sort) =>
        #be tolerant and allow {field: -1}
        unless sort?.field? and sort?.direction?
            sort.field = _.keys(sort)[0]
            sort.direction = sort[sort.field]
        
        @set 'search-sort', sort
        @reSubscribe()
        
    getSort: () =>
        @get 'search-sort'
    
    setOffset: (offset) =>
        @set 'search-offset', offset
        @reSubscribe()
        
    getOffset: () =>
        @get 'search-offset'
        
    setLimit: (limit) =>
        @set 'search-limit', limit
        @reSubscribe()
        
    getLimit: () =>
        @get 'search-limit'
        
    setSearching: (searching) =>
        @set 'searching', searching
    
    isSearching: () =>
        @get 'searching'
    
    getIndexNames: () =>
        @get 'index-names'
        
    setIndexNames: (indexNames) =>
        @set 'index-names', indexNames
        
    getExcludes: () =>
        @get 'excludes'
        
    setExcludes: (excludes) =>
        @set 'excludes', excludes
    
    find: (phrase) =>
        if phrase? and phrase.length > 0
            @clearSearch phrase
            @createIntermediaryResults phrase
            
            search = @
            Meteor.call 'spometFind', phrase, @getIndexNames(), () ->
                search.setSearching null
            
    
    clearSearch: (newPhrase) =>
        @set 'searching', if newPhrase then true else null
        @set 'current-phrase', newPhrase
        @set 'search-offset', null
        @set 'search-limit', null
        @reSubscribe()
    
    createIntermediaryResults: (phrase) =>
        phraseHash = Spomet.phraseHash phrase
        search = Spomet.Searches.find {phraseHash: phraseHash} 
        if search.count() is 0
            
            seen = {}
            
            words = phrase.split ' '
            cursor = Spomet.CommonTerms.find {token: {$in: words}} 
            
            cursor.forEach (e) ->
                e.documents.forEach (d) ->
                    [type, base, path, version] = Spomet._splitDocId d.docId
                    
                    unless seen[base]?
                        seen[base] = true
                        res = 
                            phraseHash: phraseHash 
                            score: 0
                            type: type
                            base: base
                            subDocs: {}
                            queried: new Date()
                            interim: true
                        Spomet.Searches.insert res
                    
            
    results: () =>
        phrase = @getCurrentPhrase()
        if phrase?
            opts =
                phrase: phrase
                sort: @getSort()
                offset: @getOffset()
                limit: @getLimit()
                excludes: @getExcludes()
            [selector, qOpts] = Spomet.buildSearchQuery opts
            Spomet.Searches.find selector, qOpts

