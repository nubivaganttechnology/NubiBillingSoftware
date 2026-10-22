"""Build a non-importable canonical CONTENT review from committed Phase 10A/B.
No database, HTTP client, release marker, migration or approval operation exists.
"""
import argparse
import copy
import hashlib
import json
from collections import Counter
from pathlib import Path

COLOUR = ['Fixed Colour', 'Multiple Ready Colours', 'Tintable', 'Clear/Transparent', 'Not Applicable']
COLOUR_IDS = {'colourType','colourMode','productColour','shade','shadeCode','colourFamily','baseType','baseCode'}
CORE = {'packSize','unit','soldAs'}
CHEMISTRY = {'finish','numberOfCoats','dilutionType','dilutionRatio'}
NEUTRAL_THINNERS = ['Manufacturer Recommended Thinner','Ready to Use','Two Component','N/A']
COATS = ['1','2','3','4','As Required','N/A']
FINISHES = ['Flat','Matt','Rich Matt','Smooth Matt','Satin','Silk','Sheen','High Sheen','Semi Gloss','Gloss','High Gloss','Metallic','Textured','Clear']
COLOUR_FAMILIES = ['White','Off White','Cream','Beige','Yellow','Orange','Red','Pink','Purple','Blue','Green','Brown','Grey','Black','Metallic','Clear','Other']
BASES = ['White Base','Pastel Base','Deep Base','Accent Base','Neutral Base','Clear Base']
CATEGORY_FAMILIES = {
 'SYS_CATEGORY_INTERIOR_WALL_COATINGS':'INTERIOR_COATING',
 'SYS_CATEGORY_EXTERIOR_WALL_COATINGS':'EXTERIOR_COATING',
 'SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS':'INTERIOR_EXTERIOR_COATING',
 'SYS_CATEGORY_PRIMERS_UNDERCOATS':'PRIMER',
 'SYS_CATEGORY_METAL_WOOD_ENAMELS':'ENAMEL',
 'SYS_CATEGORY_WOOD_FINISHES':'WOOD_FINISH',
 'SYS_CATEGORY_FLOOR_TILE_COATINGS':'FLOOR_COATING',
 'SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS':'INDUSTRIAL_COATING',
 'SYS_CATEGORY_PIPE_GI_COATINGS':'PIPE_GI_COATING',
 'SYS_CATEGORY_AUTOMOTIVE_COATINGS':'AUTOMOTIVE_COATING',
 'SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS':'TEXTURE_COATING',
 'SYS_CATEGORY_ALLIED_PRODUCTS':'ALLIED',
}
SPECIAL = {
 'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS':'CEILING_PAINT',
 'SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_ROOF_TILE_COATINGS':'ROOF_TILE_COATING',
 'SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ANTI_TERMITE_TREATMENT':'WOOD_TREATMENT',
 'SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE_PRIMERS':'PRIMER',
 'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WATERPROOFING_ADDITIVES_PRIMERS':'PRIMER',
}
# These exact canonical IDs have user-authorized application corrections.
APPLICATIONS = {
 'SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE': ('Roof',['Roof']),
 'SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL': ('Exterior',['Wall','Concrete']),
 'SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS': ('Interior',['Wall']),
 'SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN': ('Interior',['Wall','Floor']),
 'SYS_SUBCATEGORY_ADMIXTURES_WATERPROOFING': (None,['Concrete']),
 'SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ANTI_CORROSION_PAINT': ('Interior & Exterior',['Metal']),
 'SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_DECORATIVE_METAL_PAINT': ('Interior & Exterior',['Metal']),
 'SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ENAMEL_PAINT': ('Interior & Exterior',['Metal','Wood']),
}


def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()


def canonical_value(v):
    if isinstance(v,list):return [canonical_value(x) for x in v]
    if not isinstance(v,str):return v
    return {'Tintable Base':'Tintable','Clear / Transparent':'Clear/Transparent',
            '1 Coat':'1','2 Coats':'2','3 Coats':'3','4 Coats':'4',
            'Not Applicable':'N/A'}.get(v,v)


def options(values):
    names=[]
    for v in values:
        v=v.strip()
        if v and v.casefold() not in {n.casefold() for n in names}:names.append(v)
    return [{'id':v,'name':v,'scopeType':'SYSTEM','sortOrder':i} for i,v in enumerate(names)]


def attr(key, source, *, level='product', data_type=None, required=False, values=None, default=None):
    a=copy.deepcopy(source.get(key,{}))
    a.update(attributeId=key, displayName=a.get('displayName',key), level=level,
             dataType=data_type or a.get('dataType','TEXT'), required=required,
             defaultValue=default, options=options(values) if values is not None else a.get('options',[]),
             visibleWhen=None, requiredWhen=None, conditions=[], defaultRules=[],
             allowAddNewOption=False,allowMultiple=(data_type or a.get('dataType'))=='MULTI_SELECT')
    a.setdefault('technical',False);a.setdefault('sortOrder',0)
    a['section']='TECHNICAL' if a['technical'] else 'ESSENTIAL'
    # A stale VARIANT_FINISH semantic role must not countermand Product placement.
    a['semanticRole']={'unit':'PACK_UNIT','soldAs':'SELLING_UNIT','packSize':'PACK_SIZE',
                       'colourType':'COLOUR_MODE','finish':'PRODUCT_FINISH'}.get(key)
    if a['dataType']=='NUMBER':a['minimumExclusive']=0
    else:a['minimumExclusive']=None
    return a


def family(d):
    id_=d['canonicalCandidateId']
    if id_ in SPECIAL:return SPECIAL[id_]
    if d['family']=='POWDER':return 'PUTTY_POWDER' if d['categoryId']=='SYS_CATEGORY_PUTTY_SURFACE_PREPARATION' else 'POWDER_COATING'
    if d['family']!='VOLUME_COATING':return d['family']
    return CATEGORY_FAMILIES[d['categoryId']]


def normalize(d, evidence, common):
    id_=d['canonicalCandidateId'];r=evidence[id_];profile=r.get('profile') or{}
    f=family(d);specific=bool(profile.get('profileId'))
    declared=profile.get('optionsOverrides',profile.get('allowedOptions',{}))
    defaults=profile.get('defaults',{})
    old={a['attributeId']:copy.deepcopy(a) for a in d['attributes']}
    source={**common,**old};out={};reviews=[]
    def review(field,reason,blocking=False):
        item={'field':field,'reason':reason,'blocking':blocking,'status':'DOMAIN_REVIEW_REQUIRED'}
        if item not in reviews:reviews.append(item)
    # Retain supported attributes, but never inherit raw condition/default rules.
    supported=set(old)-{'sellingUnit','colourMode'}
    if f in {'ADHESIVE','SEALANT','ADMIXTURE','TOOLS','MASKING_TAPE','SANDPAPER','WALL_COVERING','DIY_PRESENTATION','ALLIED','WOOD_TREATMENT'}:
        supported -= CHEMISTRY | COLOUR_IDS
    if f=='ADMIXTURE':supported &= {'surface','mixingRatio','dosage','shelfLife'}|CORE
    if f=='WALL_COVERING':supported &= {'style','pattern','rollLength','rollWidth','dimensionUnit'}|CORE
    if f=='DIY_PRESENTATION':supported &= {'kitType','style','pattern','width','length','widthUnit','lengthUnit'}|CORE
    if f=='TOOLS':supported &= {'brushType','bristleMaterial','handleMaterial','brushSize','rollerType','rollerMaterial','rollerWidth','sizeUnit','toolType'}|CORE
    if f=='MASKING_TAPE':supported &= {'width','length','widthUnit','lengthUnit'}|CORE
    if f=='SANDPAPER':supported &= {'grit'}|CORE
    if f=='WOOD_TREATMENT':supported &= {'usage','surface','shelfLife'}|CORE
    if f=='SPRAY_AEROSOL':supported -= {'numberOfCoats','dilutionType','dilutionRatio','mixingRatio'}
    if f=='WATERPROOFING':supported -= COLOUR_IDS|{'finish','numberOfCoats','dilutionType','dilutionRatio'}
    if f=='PRIMER':supported -= {'finish'}
    # Colour fields are reconstructed as one consistent Product-mode contract.
    supported -= COLOUR_IDS
    for k in sorted(supported-CORE):
        a=old[k];vals=declared.get(k,[o['name'] for o in a['options']])
        value=defaults.get(k,a['defaultValue']) if specific else a['defaultValue']
        level='variant' if k in {'brushSize','rollerWidth','grit','width','length','rollWidth','rollLength','sizeUnit','widthUnit','lengthUnit','dimensionUnit'} else 'product'
        dtype=a['dataType'];vals=[canonical_value(v) for v in vals]
        if k=='finish':
            vals=[v for v in vals if v in FINISHES];value=defaults.get(k) if specific else None
            if f in {'INTERIOR_COATING','EXTERIOR_COATING','INTERIOR_EXTERIOR_COATING','CEILING_PAINT','ENAMEL'}:
                vals=[v for v in vals if v!='Clear']
        if k=='numberOfCoats':
            vals=COATS;value=canonical_value(defaults.get(k)) if specific else None
        if k=='dilutionType':
            # Unknown chemistry cannot inherit an arbitrary Wood/Epoxy solvent.
            value=defaults.get(k) if specific else None
            vals=NEUTRAL_THINNERS.copy()
            if value and canonical_value(value) not in vals:vals.insert(0,canonical_value(value))
            if value is None:
                review('dilutionType', 'Exact chemistry/thinner choice has no explicit default evidence; manufacturer-neutral options, optional and no default.')
        if k=='productColour':value=None
        out[k]=attr(k,source,level=level,data_type=dtype,required=a['required'] if level=='variant' else False,values=vals,default=canonical_value(value))
    # Source profile constraints supersede old compiled template branch residue.
    surface=defaults.get('surface') or (old.get('surface') or{}).get('defaultValue')
    usage=defaults.get('usage') or (old.get('usage') or{}).get('defaultValue')
    surf_options=declared.get('surface') or (old.get('surface') or{}).get('options',[])
    surf_options=[v['name'] if isinstance(v,dict) else v for v in surf_options]
    if f in {'INTERIOR_COATING','EXTERIOR_COATING'}:
        usage='Interior' if f=='INTERIOR_COATING' else 'Exterior';surface=['Wall'];surf_options=['Wall']
    if f=='INTERIOR_EXTERIOR_COATING':usage='Interior & Exterior'
    if f=='CEILING_PAINT':usage='Interior';surface=surf_options=['Ceiling']
    if f=='WOOD_FINISH' or f=='WOOD_TREATMENT':surface=surf_options=['Wood']
    if f=='FLOOR_COATING':usage='Floor'
    if id_ in APPLICATIONS:usage,surface=APPLICATIONS[id_];surf_options=surface
    # Keep an exact roof profile instead of forcing category-wide Wall/Floor.
    if id_=='SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ROOF_EXTERIOR_COATINGS':
        surface=surf_options=declared.get('surface',surface)
    if 'surface' in supported or f in {'CEILING_PAINT','INTERIOR_COATING','EXTERIOR_COATING','INTERIOR_EXTERIOR_COATING','ENAMEL','FLOOR_COATING','PRIMER'}:
        if surf_options:out['surface']=attr('surface',source,data_type='MULTI_SELECT',values=surf_options,default=surface)
        else:review('surface','No exact substrate set established; optional field omitted.')
    if f=='ADMIXTURE':out['surface']=attr('surface',source,data_type='MULTI_SELECT',values=['Concrete'],default=['Concrete'])
    if 'usage' in supported or f in {'CEILING_PAINT','INTERIOR_COATING','EXTERIOR_COATING','INTERIOR_EXTERIOR_COATING','FLOOR_COATING','PRIMER','ENAMEL'}:
        allowed=declared.get('usage') or [o['name'] for o in (old.get('usage') or{}).get('options',[])]
        if usage and usage not in allowed:allowed=[usage]+allowed
        if f in {'INTERIOR_COATING','CEILING_PAINT'}:allowed=['Interior']
        elif f=='EXTERIOR_COATING':allowed=['Exterior']
        elif f=='INTERIOR_EXTERIOR_COATING':allowed=['Interior & Exterior']
        elif f=='FLOOR_COATING':allowed=['Floor']
        if allowed:out['usage']=attr('usage',source,data_type='SELECT',values=allowed,default=usage)
    if f in {'ADHESIVE','SEALANT','ADMIXTURE','WALL_COVERING','TOOLS','MASKING_TAPE','SANDPAPER','DIY_PRESENTATION','ALLIED','WOOD_TREATMENT'}:
        for k in COLOUR_IDS|CHEMISTRY:out.pop(k,None)
    # Colour identity is optional at Product level and mandatory only when active.
    coloured=bool(COLOUR_IDS & set(old)) and f not in {'ADHESIVE','SEALANT','ADMIXTURE','WATERPROOFING','TOOLS','MASKING_TAPE','SANDPAPER','WALL_COVERING','DIY_PRESENTATION','ALLIED','WOOD_TREATMENT'}
    if coloured:
        if f in {'PRIMER','PUTTY_POWDER'}:modes=['Fixed Colour','Not Applicable']
        elif f in {'POWDER_COATING','SPRAY_AEROSOL'}:modes=['Fixed Colour','Multiple Ready Colours','Clear/Transparent','Not Applicable']
        else:
            authored=declared.get('colourType', [o['name'] for o in old.get('colourType',source['colourType'])['options']])
            modes=[v for v in COLOUR if v in [('Clear/Transparent' if x=='Clear / Transparent' else 'Tintable' if x=='Tintable Base' else x) for x in authored]]
        if not modes:modes=['Not Applicable']
        mode_default=defaults.get('colourType')
        mode_default={'Clear / Transparent':'Clear/Transparent','Tintable Base':'Tintable'}.get(mode_default,mode_default)
        if f in {'WOOD_FINISH','ENAMEL'} and mode_default=='Clear/Transparent':
            mode_default=None;review('colourType.defaultValue','Generic Wood/Clear default is not evidence of a fixed sellable colour mode; user chooses mode.')
        if mode_default not in modes:mode_default=None
        out['colourType']=attr('colourType',source,data_type='SELECT',values=modes,default=mode_default)
        out['colourType']['displayName']='Colour Availability'
        identities=[('productColour','Fixed Colour','product','TEXT',None,True)]
        if 'Multiple Ready Colours' in modes:
            identities += [('shade','Multiple Ready Colours','variant','TEXT',None,True),('shadeCode','Multiple Ready Colours','variant','TEXT',None,False),('colourFamily','Multiple Ready Colours','variant','SELECT',COLOUR_FAMILIES,False)]
        if 'Tintable' in modes:
            identities += [('baseType','Tintable','variant','SELECT',BASES,True),('baseCode','Tintable','variant','TEXT',None,False)]
        for key,mode,level,dtype,values,required in identities:
            if mode not in modes:continue
            condition={'attributeId':'colourType','in':[mode],'scope':'PRODUCT'}
            colour_default=defaults.get('productColour') if key=='productColour' and mode_default=='Fixed Colour' else None
            if key=='productColour':
                fixed_options=declared.get('productColour')
                if fixed_options:
                    dtype='SELECT';values=fixed_options
                elif old.get(key,{}).get('dataType')=='SELECT' and old[key]['options']:
                    dtype='SELECT';values=[o['name'] for o in old[key]['options']]
            out[key]=attr(key,source,level=level,data_type=dtype,required=required,values=values or [],default=colour_default)
            out[key]['visibleWhen']=condition
            out[key]['requiredWhen']=condition if required else None
            out[key]['conditions']=[{'targetAttributeId':'colourType','operator':'IN','expectedValues':[mode],'scope':'product'}]
    if id_=='SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS':
        out['finish']=attr('finish',source,data_type='SELECT',values=['Satin'],default='Satin')
    rules=copy.deepcopy(d['unitRules'])
    if rules['defaultSellingUnit'] is None and len(rules['allowedSellingUnits'])==1:
        rules['defaultSellingUnit']=rules['allowedSellingUnits'][0]
    for q in d['unitDomainQuestions']:
        if 'selling-unit default' in q and rules['defaultSellingUnit'] is not None:continue
        review('unitRules.materialDimension' if not rules['allowedPackUnits'] else 'unitRules.defaultSellingUnit',q,not bool(rules['allowedPackUnits']))
    # Canonical variant identity fields; no dynamic HSN/pricing attributes.
    out['packSize']=attr('packSize',source,level='variant',data_type='NUMBER',required=True)
    out['unit']=attr('unit',source,level='variant',data_type='SELECT',required=True,values=rules['allowedPackUnits'],default=rules['defaultPackUnit'])
    out['soldAs']=attr('soldAs',source,level='variant',data_type='SELECT',required=True,values=rules['allowedSellingUnits'],default=rules['defaultSellingUnit'])
    for k in ['hsnCode','hsnSac','purchaseRate','sellingPrice','mrp']:out.pop(k,None)
    # Validate all authored defaults, instead of depending on resolver discards.
    for k,a in out.items():
        vals=[o['name'] for o in a['options']]
        value=a['defaultValue']
        if value is not None and a['dataType'] in {'SELECT','MULTI_SELECT'}:
            valid=(value in vals) if a['dataType']=='SELECT' else isinstance(value,list) and all(v in vals for v in value)
            if not valid:
                a['defaultValue']=None
                review(k+'.defaultValue','Source default conflicts with the explicit option contract; cleared pending exact product evidence.')
        if a['dataType'] in {'SELECT','MULTI_SELECT'}:
            a['options']=options(vals)
        if a['dataType']=='SELECT' and not a['options']:
            review(k,'Required unit identity cannot be resolved without exact material evidence.',True)
    order=['usage','surface','colourType','productColour','finish','segment','numberOfCoats','dilutionType','brushType','bristleMaterial','handleMaterial','rollerType','rollerMaterial','toolType','style','kitType','shade','shadeCode','colourFamily','baseType','baseCode','brushSize','rollerWidth','grit','width','length','rollWidth','rollLength','sizeUnit','widthUnit','lengthUnit','dimensionUnit','packSize','unit','soldAs']
    attrs=sorted(out.values(),key=lambda a:(a['level'],a['technical'],order.index(a['attributeId']) if a['attributeId'] in order else 1000,a['attributeId']))
    for i,a in enumerate(attrs):a['sortOrder']=i
    delta=[]
    for k in sorted(set(old)|set(out)):
        if k not in old:delta.append({'attributeId':k,'change':'ADDED','reason':'Canonical family/variant identity contract'})
        elif k not in out:delta.append({'attributeId':k,'change':'REMOVED','reason':'Irrelevant family content or replaced canonical unit/colour field'})
        else:
            for field,label in [('level','PLACEMENT'),('required','REQUIREDNESS'),('dataType','TYPE'),('defaultValue','DEFAULT'),('options','OPTIONS'),('visibleWhen','CONDITION'),('requiredWhen','REQUIRED_CONDITION'),('defaultRules','DEFAULT_RULE'),('semanticRole','ROLE'),('allowAddNewOption','CUSTOM_OPTION_POLICY'),('allowMultiple','MULTIPLICITY')]:
                before=old[k].get(field);after=out[k].get(field)
                if field=='options':before=[v['name'] for v in before];after=[v['name'] for v in after]
                if before!=after:delta.append({'attributeId':k,'change':label,'before':before,'after':after,'reason':'Explicit family/profile content contract'})
    if rules!=d['unitRules']:
        delta.append({'attributeId':'unitRules','change':'UNIT_RULE','before':d['unitRules'],'after':rules,'reason':'The sole explicit profile-specific selling unit is the only possible default; no global fallback or material assumption.'})
    review_items=sorted(reviews,key=lambda q:(q['field'],q['reason']))
    return {'canonicalId':id_,'categoryId':d['categoryId'],'name':d['name'],'family':f,
      'intendedSelectability':'DOMAIN_REVIEW_REQUIRED' if any(q['blocking'] for q in reviews) else 'SELECTABLE_READY',
      'attributes':attrs,'unitRules':rules,'conversionDefault':False,
      'levels':{a['attributeId']:a['level'] for a in attrs},
      'requiredness':{a['attributeId']:{'requiredWhenVisible':a['required'],'requiredWhen':a['requiredWhen']} for a in attrs},
      'options':{a['attributeId']:[o['name'] for o in a['options']] for a in attrs if a['options']},
      'defaults':{a['attributeId']:a['defaultValue'] for a in attrs if a['defaultValue'] is not None},
      'conditions':{a['attributeId']:a['visibleWhen'] for a in attrs if a['visibleWhen']},
      'remainingDomainReviews':review_items,'changes':delta,
      'sourceEvidence':{'phase10bCandidateId':id_,'phase10aDocumentId':r['documentId'],'installedPayloadId':r['payloadSubcategoryId'],
         'profileId':profile.get('profileId'),'profileDigest':digest(profile),'sourceContractDigest':digest(d),
         'templateGroupSource':d.get('templateSemanticsSource','PHASE10A_DECODED_CANONICAL_CANDIDATE'),
         'authoredDocumentTemplateDigest':digest(d['authoredTemplateContract']) if 'authoredTemplateContract' in d else None,
         'ruleAuthority':'PHASE_10C_USER_FAMILY_AND_PLACEMENT_CONTRACT'},
      'migrationApproved':False,'approvedForLiveExecution':False}


def build(intent,evidence):
    by_id={r['documentId']:r for r in evidence['records']}
    common={}
    for d in sorted(intent['canonicalContentCandidates'],key=lambda d:d['canonicalCandidateId']):
        for a in d['attributes']:common.setdefault(a['attributeId'],a)
    candidates=[normalize(d,by_id,common) for d in sorted(intent['canonicalContentCandidates'],key=lambda d:d['canonicalCandidateId'])]
    result={'kind':'CANONICAL_CONTENT_REVIEW_ONLY','schemaVersion':1,'importable':False,'approvedForLiveExecution':False,
        'sourceIntentFingerprint':intent['intentFingerprint'],'sourceAuditDigest':digest(evidence),
        'candidates':candidates,'noncanonicalRecords':[copy.deepcopy(r) for r in intent['records'] if r['intendedSelectability'] in {'EXCLUDED','DISABLED_DOMAIN_REVIEW','DUPLICATE_REVIEW'}],
        'duplicateDecisions':[{'name':p['name'],'canonicalId':p['canonicalCandidateId'],'legacyId':p['legacyCandidateId'],
          'sourceSemanticConflicts':p['semanticConflictSummary'],'contentDecisions':next(d['changes'] for d in candidates if d['canonicalId']==p['canonicalCandidateId']),
          'approved':False,'migrationApproved':False} for p in sorted(intent['duplicateReviewManifest'],key=lambda p:p['canonicalCandidateId'])],
        'identityMismatchReview':[{'prospectiveCanonicalId':r['prospectiveCanonicalId'],'installedPayloadId':r['installedPayloadId'],'approved':False,'migrationApproved':False} for r in intent['identityMismatchReview']]}
    definitions={}
    for d in candidates:
        for a in d['attributes']:
            definition={'attributeId':a['attributeId'],'name':a['displayName'],
                'dataType':a['dataType'],'attributeLevel':a['level'].upper(),
                'semanticRole':a['semanticRole'],'required':False,'status':'ACTIVE','scopeType':'SYSTEM'}
            if a['attributeId']=='productColour':definition['dataType']='TEXT'
            previous=definitions.get(a['attributeId'])
            if previous is not None:
                assert previous['dataType']==definition['dataType'] and previous['attributeLevel']==definition['attributeLevel']
            definitions[a['attributeId']]=definition
    result['attributeDefinitions']=[definitions[k] for k in sorted(definitions)]
    result['canonicalProductFields']=['Product Name','Brand','Category','Subcategory','HSN/SAC','Description','Product Image','Status']
    result['canonicalVariantFields']=['SKU','Barcode','Pack Size','Pack Unit','Selling Unit','Base Unit when conversion enabled','Conversion Factor when conversion enabled']
    result['formSections']=['Product Identity','Product Specifications','Sellable Variants / SKUs','Technical Details','Product Image']
    result['counts']={'candidates':len(candidates),'selectableReady':sum(d['intendedSelectability']=='SELECTABLE_READY' for d in candidates),
      'domainBlocked':sum(d['intendedSelectability']=='DOMAIN_REVIEW_REQUIRED' for d in candidates),
      'schemaResiduePromoted':sum(next(d['intendedSelectability'] for d in candidates if d['canonicalId']==r['documentId'])=='SELECTABLE_READY' for r in intent['records'] if r['schemaResidue']),
      'changeCounts':dict(sorted(Counter(v['change'] for d in candidates for v in d['changes']).items()))}
    comparisons={p['preferredCanonicalCandidate']:p for p in evidence['duplicateComparisons']}
    for decision in result['duplicateDecisions']:
        target=next(d for d in candidates if d['canonicalId']==decision['canonicalId'])
        decision['semanticDecisions']=[{'path':v['path'],
            'canonicalContentId':decision['canonicalId'],
            'leftEvidenceDigest':digest(v.get('left')),'rightEvidenceDigest':digest(v.get('right')),
            'disposition':'USE_CORRECTED_CANONICAL_FAMILY_CONTRACT_ONLY',
            'reason':'Retain verified canonical profile content and apply explicit Phase 10C rules; conflicting legacy fields are not unioned into the canonical form.',
            'correctedContentDigest':digest({'attributes':target['attributes'],'unitRules':target['unitRules']}),
            'legacyRecordDisposition':'UNCHANGED_IN_PRODUCTION', 'migrationApproved':False}
            for v in comparisons[decision['canonicalId']]['differences']]
    result['fingerprint']=logical_fingerprint(result)
    return result

def logical_fingerprint(model):
    logical=copy.deepcopy(model)
    logical.pop('fingerprint',None)
    logical.pop('sourceAuditDigest',None)
    for d in logical['candidates']:
        d['sourceEvidence'].pop('sourceContractDigest',None)
    return digest(logical)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',default='docs/phase10c-canonical-content.json');args=parser.parse_args()
    target=Path(args.output).resolve()
    if target!=Path('docs/phase10c-canonical-content.json').resolve():raise ValueError('Only the separate Phase 10C review artifact may be written')
    result=build(json.loads(Path('docs/phase10b-intended-catalogue.json').read_text()),json.loads(Path('docs/phase10a-catalogue-audit.json').read_text()))
    target.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n');print(json.dumps(result['counts'],sort_keys=True))
