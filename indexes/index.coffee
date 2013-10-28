indexTokens = (docId, tokens, collection) ->
    tokens.forEach (token) ->
        doc = 
            docId: docId
            pos: token.pos
        
        t = collection.findOne {token: token.token}
        if t?
            upd = {$push: {documents: doc}}
            unless doc.docId in (t.documents.map (d) -> d.docId)
                upd['$inc'] = {documentsCount: 1} 
                
            collection.update {token: token.token}, upd
        else
            collection.insert 
                token: token.token,
                tlength: token.tlength, 
                documentsCount: 1, 
                documents: [doc]

documentsCountWithToken = (collection, token) ->
    collection.findOne({token: token})?.documentsCount

tfidf = (termCountInDocument, documentLength, mostCommonTermCountInDocument, allDocumentsCount, documentsCountWithTerm) ->
    tf = termCountInDocument / Math.log(documentLength * mostCommonTermCountInDocument)
    idf = Math.log (1 + allDocumentsCount) / documentsCountWithTerm
    tf * idf
    
findWithTokenizer = (tokenizer, callback) ->
    found = {}
    tokenizer.tokens.forEach (token) ->
        tokenizer.collection.find({token: token.token}).forEach (t) ->
            t.documents.forEach (d) ->
                callback? t.token, d.docId, d.pos
                if found[d.docId]
                    found[d.docId].push {token: t.token, pos: d.pos}
                else
                    found[d.docId] = [{token: t.token, pos: d.pos}]
    found

rate = (docId, tokenCounts) ->
    score = 0
    para = Documents.ratingParams docId
    (_.values tokenCounts).forEach (data) ->
        score += data.indexBoost * tfidf data.tokenCountInDoc, 
            para.dlength, 
            para.mostCommonTermCount, 
            para.documentsCount, 
            data.documentsCountWithToken,
            data.indexBoost
    score


Index.add = (docSpec) ->
    if docSpec.base? and docSpec.text?
        unless docSpec.type? then docSpec.type = 'default'
        unless docSpec.path? then docSpec.path = '/'
        docSpec.version = Documents.nextVersion docSpec
        
        #init indexer for each index
        tokenizers = Spomet.options.indexes.map (i) ->
            new i.Tokenizer
        
        #normalize and tokenize over all indexes in one go
        docSpec.text.split('').forEach (c, pos) ->
            tokenizers.forEach (t) ->
                t.parseCharacter c, pos
    
        docId = Spomet._docId docSpec
        tokenizers.forEach (t) ->
            t.finalize()
            indexTokens docId, t.tokens, t.collection
        
        Documents.add docSpec, tokenizers.map((i) -> i.tokens).reduce (s, a) -> s.concat a
    
    docSpec
    
    
Index.reset = () ->
    Documents.collection.remove {}
    Spomet.options.indexes.forEach (index) ->
        index.collection.remove {}
            
Index.setup = () ->
    Documents.collection._ensureIndex {docId: 1}
    Documents.collection._ensureIndex {type: 1, base: 1, path: 1}
    
    Spomet.options.indexes.forEach (index) ->
        index.collection._ensureIndex {token: 1}
    
Index.remove = (docId, indexName, remToken) ->
    ind = i for i in Spomet.options.indexes when i.name is indexName
    ind.collection.update {token: remToken},
        $pull: {documents: {docId: docId}}
        $inc: {documentsCount: -1}
            
    
Index.find = (phrase, callback, indexes) ->
    unless indexes?
        indexes = Spomet.options.indexes
        
    tokenizers = indexes.map (index) -> new index.Tokenizer
    phrase.split('').forEach (c, i) ->
        tokenizers.forEach (t) ->
            t.parseCharacter c, i
    
    found = {}
    tCounts = {}
    tokenizers.forEach (t) -> 
        t.finalize()
        findWithTokenizer t, (token, docId, pos) ->
            unless tCounts[docId]? then tCounts[docId] = {}
            subCounts = tCounts[docId]
            
            key = token + t.indexName
            if subCounts[key]?
                subCounts[key].tokenCountInDoc += 1
            else 
                subCounts[key] =
                    token: token
                    tokenCountInDoc: 1
                    documentsCountWithToken: documentsCountWithToken t.collection, token
                    indexBoost: t.indexBoost
                    
            if found[docId]
                found[docId].tokens.push 
                    indexName: t.indexName
                    token: token
                    pos: pos
            else
                found[docId] = 
                    tokens: [{indexName: t.indexName, token: token, pos: pos}]
                
            found[docId].score = rate docId, tCounts[docId]
            callback? docId, found[docId].tokens, found[docId].score

Spomet.Index = @Index

Meteor.startup = () ->
    Index.setup()
