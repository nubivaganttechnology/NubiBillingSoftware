"""Generate an isolated non-importable intent model from committed audit evidence.
No SQLite connection, live import, network, migration or approval operation exists.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

VOLUME_CATEGORIES = {
 'SYS_CATEGORY_INTERIOR_WALL_COATINGS','SYS_CATEGORY_EXTERIOR_WALL_COATINGS',
 'SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS','SYS_CATEGORY_PRIMERS_UNDERCOATS',
 'SYS_CATEGORY_METAL_WOOD_ENAMELS','SYS_CATEGORY_WOOD_FINISHES',
 'SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS','SYS_CATEGORY_FLOOR_TILE_COATINGS',
 'SYS_CATEGORY_PIPE_GI_COATINGS','SYS_CATEGORY_AUTOMOTIVE_COATINGS',
 'SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS','SYS_CATEGORY_ALLIED_PRODUCTS'}
SPECIFIC = {
 'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH':'TOOLS',
 'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_ROLLER':'TOOLS',
 'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_MASKING_TAPE':'MASKING_TAPE',
 'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_SANDPAPER_ABRASIVES':'SANDPAPER',
 'SYS_SUBCATEGORY_SYS_CATEGORY_POWDER_COATINGS_POWDER_COATINGS':'POWDER',
 'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_SPRAY_PAINTS':'SPRAY_AEROSOL',
 'SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_STENCILS_WALL_ART':'DIY_PRESENTATION',
 'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS':'DIY_PRESENTATION',
 'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_STICKERS':'DIY_PRESENTATION'}
MEASUREMENTS={'Litre':'VOLUME','Millilitre':'VOLUME','Kilogram':'MASS','Gram':'MASS'}


def unit_contract(record):
    id_=record['documentId']; category=record['categoryId']; profile=record['profile'] or {}
    warnings=[]; family=SPECIFIC.get(id_)
    if not family:
        family = ('POWDER' if category=='SYS_CATEGORY_PUTTY_SURFACE_PREPARATION' else
                  'ADMIXTURE' if category=='SYS_CATEGORY_ADMIXTURES' else
                  'TOOLS' if category=='SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES' else
                  'WALL_COVERING' if category=='SYS_CATEGORY_WALL_COVERINGS' else
                  'SEALANT' if category=='SYS_CATEGORY_SEALANTS_REPAIR' else
                  'WATERPROOFING' if category=='SYS_CATEGORY_WATERPROOFING' else
                  'ADHESIVE' if category=='SYS_CATEGORY_ADHESIVES_TILING' else
                  'VOLUME_COATING' if category in VOLUME_CATEGORIES else 'DOMAIN_REVIEW_REQUIRED')
    packs=[]; bases=[]; dimension=None; conversion=False; default=None
    if family in {'VOLUME_COATING','ADMIXTURE'}:
        packs=bases=['Litre','Millilitre']; dimension='VOLUME'; conversion=True; default='Litre'
    elif family=='POWDER':
        packs=bases=['Kilogram','Gram']; dimension='MASS'; conversion=True; default='Kilogram'
    elif family in {'TOOLS','SANDPAPER','MASKING_TAPE','WALL_COVERING'}:
        default={'TOOLS':'Piece','SANDPAPER':'Sheet','MASKING_TAPE':'Roll','WALL_COVERING':'Roll'}[family]
        packs=bases=[default]
    elif family in {'WATERPROOFING','ADHESIVE'}:
        allowed=profile.get('allowedUnits',[])
        dimensions={MEASUREMENTS[u] for u in allowed if u in MEASUREMENTS}
        if len(dimensions)==1 and allowed and all(u in MEASUREMENTS for u in allowed):
            dimension=next(iter(dimensions));packs=bases=list(allowed)
            default='Litre' if dimension=='VOLUME' else 'Kilogram'
            if default not in packs:default=packs[0]
            if family=='ADHESIVE' and dimension=='VOLUME':
                warnings.append('DOMAIN_REVIEW_REQUIRED: confirm explicit liquid-adhesive evidence before using this volume contract')
        else:
            warnings.append('DOMAIN_REVIEW_REQUIRED: select one supported material dimension; installed profile mixes or omits dimensions')
    elif family in {'SEALANT','SPRAY_AEROSOL','DIY_PRESENTATION'}:
        packs=list(profile.get('allowedUnits',[]));default=profile.get('defaults',{}).get('unit',profile.get('defaults',{}).get('sellingUnit'))
        if not packs or default not in packs:
            warnings.append('DOMAIN_REVIEW_REQUIRED: exact packaging/content default is not established')
            default=None
        # Exact content is not established; no measurement base is inferred.
    else:
        warnings.append('DOMAIN_REVIEW_REQUIRED: no explicit family unit contract')
    selling=list(profile.get('allowedSellingUnits',profile.get('allowedSoldAs',[])))
    if family in {'TOOLS','SANDPAPER','MASKING_TAPE','WALL_COVERING'}:
        selling=[default]
    if not selling:selling=list(packs)
    if dimension:
        selling=[u for u in selling if u not in MEASUREMENTS or MEASUREMENTS[u]==dimension]
    default_selling=profile.get('defaults',{}).get('soldAs',profile.get('defaults',{}).get('sellingUnit'))
    if default_selling not in selling:
        default_selling=default if default in selling else None
    if default_selling is None and selling:
        warnings.append('DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default')
    return family, {'allowedPackUnits':packs,'defaultPackUnit':default,
      'allowedBaseUnits':bases,'defaultBaseUnit':default if default in bases else None,
      'allowedSellingUnits':selling,'defaultSellingUnit':default_selling,
      'conversionAllowed':conversion,'conversionDimension':dimension,
      'conversionRequiresExplicitFactor':True}, warnings


def normalized_form(record, rules):
    attrs=copy.deepcopy(record['productAttributes']+record['variantAttributes'])
    # These are candidate content contracts, not new template rows or IDs.
    for a in attrs:
        if a['attributeId'] in {'unit','packUnit','soldAs','commercialUnit','sellingUnit'}:
            selling=a['attributeId'] in {'soldAs','commercialUnit','sellingUnit'}
            allowed=rules['allowedSellingUnits' if selling else 'allowedPackUnits']
            a['options']=[{'id':u,'name':u,'scopeType':'SYSTEM','sortOrder':i} for i,u in enumerate(allowed)]
            a['defaultValue']=rules['defaultSellingUnit' if selling else 'defaultPackUnit']
        if record['documentId'] in {'SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING','SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING'} and a['attributeId']=='usage':
            # Explicit pair IDs, rather than a display-name compiler heuristic.
            if record['documentId'] in {'SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING','SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING'}:
                if not any(o['name']=='Floor' for o in a['options']):
                    a['options'].append({'id':'usage_Floor','name':'Floor','scopeType':'SYSTEM','sortOrder':len(a['options'])})
                a['defaultValue']='Floor'
    return sorted(attrs,key=lambda a:(a['level'],a['sortOrder'],a['attributeId']))


def build(evidence):
    records=sorted(evidence['records'],key=lambda r:r['documentId'])
    pairs=sorted(evidence['duplicateComparisons'],key=lambda p:p['preferredCanonicalCandidate']); legacy={p['legacyCandidate'] for p in pairs}
    residue={d['documentId'] for d in evidence['disabledDispositions'] if d['disposition']=='PROBABLY_SHOULD_BE_SELECTABLE'}
    entries=[];definitions=[];reviews=[]
    for r in records:
        id_=r['documentId'];family,rules,warnings=unit_contract(r)
        excluded = r['classification'] in {'UNAVAILABLE','BUSINESS_SCOPE_EXCLUDED','MISSING_TEMPLATE'}
        intent=('DISABLED_DOMAIN_REVIEW' if r['subcategoryName']=='Miscellaneous' else
                'EXCLUDED' if excluded else
                'DUPLICATE_REVIEW' if id_ in legacy else
                'SELECTABLE_PENDING_CONTENT_VALIDATION')
        entry={'documentId':id_,'installedPayloadId':r['payloadSubcategoryId'],
          'categoryId':r['categoryId'],'name':r['subcategoryName'],
          'installedTemplateSelectable':r['templateSelectable'],
          'schemaResidue':id_ in residue,'intendedSelectability':intent,
          'unitFamily':family,'unitRules':rules,'domainQuestions':warnings,'approved':False}
        entries.append(entry)
        if not excluded and id_ not in legacy:
            attrs=normalized_form(r,rules)
            definitions.append({'canonicalCandidateId':id_,'categoryId':r['categoryId'],
              'name':r['subcategoryName'],'family':family,'intendedSelectability':intent,
              'allowedAttributes':[a['attributeId'] for a in attrs],
              'attributes':attrs,'unitRules':rules,'contentValidation':'PENDING',
              'unitDomainQuestions':warnings,
              'domainQuestions':warnings + [d['message'] for d in r['resolverDiagnostics'] if d['code']=='DOMAIN_REVIEW_REQUIRED'],
              'approved':False})
    # Prospective mismatch definitions use the current document's template group.
    # Never graft the old payload-ID orphan group onto the prospective identity.
    for mismatch in evidence['identityMismatchReview']:
        definition=next(d for d in definitions if d['canonicalCandidateId']==mismatch['documentId'])
        record=next(r for r in records if r['documentId']==mismatch['documentId'])
        inherited={a['attributeId']:a for a in record['productAttributes']+record['variantAttributes']}
        document_attrs=[]
        for row in mismatch['documentTemplates']:
            attr=copy.deepcopy(inherited[row['attributeId']])
            for key in ['required','defaultValue','dataType','section','sortOrder','visibleWhen','requiredWhen','defaultRules']:
                if key in row:attr[key]=copy.deepcopy(row[key])
            if 'attributeLevel' in row:attr['level']='variant' if row['attributeLevel']=='VARIANT' else 'product'
            if isinstance(row.get('options'),list):
                attr['options']=[{'id':value,'name':value,'scopeType':'SYSTEM','sortOrder':i} for i,value in enumerate(row['options'])]
            if 'visibleWhen' in row:attr['conditions']=[] # resolver evaluates the authored visibleWhen map
            document_attrs.append(attr)
        prospective={**record,'productAttributes':[a for a in document_attrs if a['level']=='product'],
                     'variantAttributes':[a for a in document_attrs if a['level']=='variant']}
        definition['attributes']=normalized_form(prospective,definition['unitRules'])
        definition['allowedAttributes']=[a['attributeId'] for a in definition['attributes']]
        definition['templateSemanticsSource']='CURRENT_DOCUMENT_TEMPLATE_GROUP'
        definition['authoredTemplateContract']=copy.deepcopy(mismatch['documentTemplates'])
        definition['domainQuestions'].append('Reconcile global attribute definitions against this document-ID group before content approval; old payload-ID group remains separate.')
    by_id={d['canonicalCandidateId']:d for d in definitions}
    for p in pairs:
        reviews.append({'name':p['name'],'canonicalCandidateId':p['preferredCanonicalCandidate'],
          'legacyCandidateId':p['legacyCandidate'],'semanticConflictSummary':[d['path'] for d in p['differences']],
          'recommendedCanonicalContract':by_id[p['preferredCanonicalCandidate']],
          'remainingDomainQuestion':'Confirm intended requiredness/defaults/options/placement and material/packaging semantics; compiler identity preference is not migration approval.',
          'approved':False,'migrationApproved':False})
    mismatches=[{'name':r['name'],'prospectiveCanonicalId':r['documentId'],'installedPayloadId':r['payloadId'],
      'prospectiveContract':by_id[r['documentId']], 'approved':False,'migrationApproved':False,
      'remainingDomainQuestion':'Confirm prospective document-ID form; retain both non-equivalent installed template groups.'} for r in evidence['identityMismatchReview']]
    family_forms={}
    for d in definitions:family_forms.setdefault(d['family'],[]).append(d['canonicalCandidateId'])
    model = {'kind':'CATALOGUE_INTENT_REVIEW_ONLY','schemaVersion':1,'importable':False,
      'approvedForLiveExecution':False,'sourceAuditSha256':hashlib.sha256(json.dumps(evidence,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
      'records':entries,'canonicalContentCandidates':definitions,
      'familyForms':family_forms,'duplicateReviewManifest':reviews,'identityMismatchReview':mismatches,
      'counts':{'records':len(entries),'schemaResiduePendingContent':sum(e['schemaResidue'] and e['intendedSelectability']=='SELECTABLE_PENDING_CONTENT_VALIDATION' for e in entries),
         'canonicalContentCandidates':len(definitions),'conversionAllowedTrue':sum(d['unitRules']['conversionAllowed'] for d in definitions),
         'conversionAllowedFalse':sum(not d['unitRules']['conversionAllowed'] for d in definitions),
         'unitDomainReviewCandidates':sum(bool(d['unitDomainQuestions']) for d in definitions)},
      'conversionDefaultsEnabled':False}
    model['intentFingerprint']=hashlib.sha256(json.dumps({k:v for k,v in model.items() if k!='sourceAuditSha256'},sort_keys=True,separators=(',',':')).encode()).hexdigest()
    return model

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',required=True);args=parser.parse_args()
    p=Path(args.output).resolve()
    if p.suffix!='.json' or not p.is_relative_to(Path('docs').resolve()):raise ValueError('Only a separate docs JSON review artifact is permitted')
    model=build(json.loads(Path('docs/phase10a-catalogue-audit.json').read_text()))
    p.write_text(json.dumps(model,indent=2,ensure_ascii=False)+'\n');print(json.dumps(model['counts']))
