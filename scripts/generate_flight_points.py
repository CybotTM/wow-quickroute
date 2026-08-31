import csv, re, collections, json, sys

tn = list(csv.DictReader(open('TaxiNodes.csv', encoding='utf-8')))
tp = list(csv.DictReader(open('TaxiPath.csv', encoding='utf-8')))
um = list(csv.DictReader(open('UiMap.csv', encoding='utf-8')))
ua = list(csv.DictReader(open('UiMapAssignment.csv', encoding='utf-8')))

deg = collections.defaultdict(set)
for r in tp:
    deg[r['FromTaxiNode']].add(r['ToTaxiNode']); deg[r['ToTaxiNode']].add(r['FromTaxiNode'])
degree = {k: len(v - {k}) for k, v in deg.items()}

uimap = {r['ID']: r for r in um}
boxes = collections.defaultdict(list)
for r in ua:
    m = uimap.get(r['UiMapID'])
    if not m or m['Type'] != '3': continue
    try:
        x0,y0,x1,y1 = float(r['Region_0']),float(r['Region_1']),float(r['Region_3']),float(r['Region_4'])
        a0,b0,a1,b1 = float(r['UiMin_0']),float(r['UiMin_1']),float(r['UiMax_0']),float(r['UiMax_1'])
    except ValueError: continue
    box = (min(x0,x1),max(x0,x1),min(y0,y1),max(y0,y1))
    boxes[r['MapID']].append((box,(x0,y0,x1,y1,a0,b0,a1,b1),int(r['UiMapID'])))

def norm(s): return re.sub(r'[^a-z]','', s.lower())
def related(a,b):
    a,b = norm(a), norm(b)
    return bool(a) and bool(b) and (a.startswith(b) or b.startswith(a))

kept = []
counts = collections.Counter()
for node in tn:
    if degree.get(node['ID'], 0) < 2: counts['dropped: fewer than 2 neighbours'] += 1; continue
    px, py = float(node['Pos_0']), float(node['Pos_1'])
    best = None
    for box, proj, uid in boxes.get(node['ContinentID'], ()):
        if box[0] <= px <= box[1] and box[2] <= py <= box[3]:
            area = (box[1]-box[0])*(box[3]-box[2])
            if best is None or area < best[0]: best = (area, uid, proj)
    if not best: counts['dropped: no zone box contains it'] += 1; continue
    _, uid, (x0,y0,x1,y1,a0,b0,a1,b1) = best
    zname = uimap[str(uid)]['Name_lang'].strip()
    if ',' in node['Name_lang']:
        place, stated = [s.strip() for s in node['Name_lang'].rsplit(',', 1)]
        stated = re.sub(r'\[.*?\]', '', stated).strip()
        # The name must corroborate the zone: either it names the zone itself,
        # or it names a place whose own name IS the zone (a city inside a zone,
        # "Ironforge, Dun Morogh" -> zone Ironforge).
        if not (related(zname, stated) or related(zname, place)):
            counts['dropped: name contradicts geometry'] += 1; continue
    nx = (px-x0)/(x1-x0) if x1 != x0 else 0.0
    ny = (py-y0)/(y1-y0) if y1 != y0 else 0.0
    kept.append({'uid':uid,'x':a0+nx*(a1-a0),'y':b0+ny*(b1-b0),'wx':px,'wy':py,
                 'cont':int(node['ContinentID']),'name':node['Name_lang'],
                 'deg':degree.get(node['ID'],0),'id':int(node['ID']),'zone':zname})

for k in sorted(counts): print(f"{k:<38}: {counts[k]}", file=sys.stderr)
print(f"{'kept':<38}: {len(kept)}", file=sys.stderr)

best = {}
for k in kept:
    cur = best.get(k['uid'])
    if cur is None or (-k['deg'], k['id']) < (-cur['deg'], cur['id']): best[k['uid']] = k
final = {u:v for u,v in best.items() if 0.0 < v['x'] < 1.0 and 0.0 < v['y'] < 1.0}
print(f"{'zones with a flight master':<38}: {len(final)}", file=sys.stderr)
json.dump({str(k):v for k,v in final.items()}, open('flightpoints.json','w'))

resid = [(u,v) for u,v in sorted(final.items()) if ',' in v['name']
         and not related(v['zone'], re.sub(r'\[.*?\]','',v['name'].rsplit(',',1)[1]).strip())]
print(f"{'residual: city-inside-zone rows':<38}: {len(resid)}", file=sys.stderr)
for u,v in resid: print(f"   [{u:>4}] {v['zone']:<22} <- {v['name']}", file=sys.stderr)
