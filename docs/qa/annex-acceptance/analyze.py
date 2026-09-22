"""Read scratch dump only. Exact pixel-center coverage of generated UV triangle union.
Coverage is unique texels per rendered material surface, not image-wide color average.
Nearest texel classification intentionally excludes filtering/mipmap/lighting/tint effects.
"""
import argparse, json, math, hashlib
from pathlib import Path
import numpy as np
from PIL import Image
ROOT: Path
PALETTE={'BayFloor':('375b7a',.90),'LoftDeck':('b7602d',.90),'Ceiling':('282623',.85),
 **{n:('c68437',.85) for n in ['WallN','WallE','WallW','WallS_L','WallS_R','DoorLintel','BayPier','BayHalfWall']},
 **{n:('110f0c',.80) for n in ['DoorJambL','DoorJambR']}}
def footprint(uv, indices, size, repeat):
 w,h=size; mask=np.zeros((h,w),dtype=bool); degenerate=0
 for k in range(0,len(indices),3):
  t=uv[indices[k:k+3]]; lo=t.min(axis=0); hi=t.max(axis=0)
  if not repeat and (np.any(lo<0) or np.any(hi>1)):
   return None,'clamped out-of-range UV footprint not measured'
  if np.any(hi-lo>32): return None,'UV spans over 32 texture repeats; not measured'
  a,b,c=t; d=(b-a)[0]*(c-a)[1]-(b-a)[1]*(c-a)[0]
  if abs(d)<1e-14: degenerate+=1; continue
  # Evaluate texel centers in unbounded UV space, modulo image dimensions for repeat.
  xmin,xmax=math.ceil(lo[0]*w-.5),math.floor(hi[0]*w-.5)
  ymin,ymax=math.ceil(lo[1]*h-.5),math.floor(hi[1]*h-.5)
  if xmax-xmin>32768 or ymax-ymin>32768: return None,'UV footprint too large; not measured'
  for y in range(ymin,ymax+1):
   xs=np.arange(xmin,xmax+1); p=np.stack(((xs+.5)/w,np.full(xs.shape,(y+.5)/h)),axis=-1)-a
   u=(p[:,0]*(c-a)[1]-p[:,1]*(c-a)[0])/d
   v=((b-a)[0]*p[:,1]-(b-a)[1]*p[:,0])/d
   inside=(u>=-1e-10)&(v>=-1e-10)&(u+v<=1+1e-10)
   mask[y%h,xs[inside]%w]=True
 return mask, f'{degenerate} zero-area UV triangles excluded' if degenerate else ''
def analyze_surface(node,s):
 m=s['material']; out={'surface':s['surface'],'material':m.get('resource'),'tint':m.get('albedo_color')}
 target=PALETTE.get(node)
 if node=='RelayRack':
  rid=m.get('resource','')+' '+m.get('albedo',{}).get('resource','')
  if s.get('material_slot') == 4 or '3kojc' in rid or 'tyis1' in rid or 'relay_rack_body.res' in rid: target=('0c0c0f',.90)
  elif s.get('material_slot') == 6 or '2nh6n' in rid or '42fty' in rid or 'relay_rack_bezel.res' in rid: target=('f28c14',.95)
 if not target: out['brief_target']='not assigned'; return out
 out['target_hex'],out['floor']=target
 if m.get('unsupported') or m.get('triplanar'):out['missing']='unsupported shader/triplanar mapping';return out
 if not m.get('albedo',{}).get('path'):
  out.update(pixel_paint_coverage=0,passes=False,missing='no albedo image; material tint is not pixel paint');return out
 im=np.array(Image.open(m['albedo']['path']).convert('RGBA'))
 uv=np.array(s['uv'],dtype=float)
 if len(uv)!=len(s['vertices']):out['missing']='missing generated UVs';return out
 uv=uv*np.array(m['uv_scale'][:2])+np.array(m['uv_offset'][:2])
 indices=s['indices'] or list(range(len(uv)))
 mask,note=footprint(uv,indices,(im.shape[1],im.shape[0]),m['repeat'])
 if mask is None:out['missing']=note;return out
 n=int(mask.sum());out.update(footprint_texels=n,method='union of pixel centers inside actual generated UV triangles',note=note)
 if not n:out['missing']='no covered pixel centers; subpixel/degenerate UVs';return out
 rgb=np.array([int(target[0][i:i+2],16) for i in (0,2,4)])
 pixels=im[mask].astype(float)
 # Explicit tolerance accepts minor paint/encoding variation, not a white image tinted in material.
 good=(np.max(np.abs(pixels[:,:3]-rgb),axis=1)<=31)&(pixels[:,3]>=230)
 out.update(pixel_paint_coverage=float(good.mean()),passes=bool(good.mean()>=target[1]),palette_max_channel_tolerance=31)
 if m.get('emission_enabled') and m.get('emission',{}).get('path'):
  emission=np.array(Image.open(m['emission']['path']).convert('RGB'))
  out['emission_image_size']=[emission.shape[1],emission.shape[0]]
  lit=emission.max(axis=2)>10
  yy,xx=np.where(lit)
  out['emission_nonblack_pixels_whole_image']=int(lit.sum())
  out['emission_bbox_pixels']=[int(xx.min()),int(yy.min()),int(xx.max()),int(yy.max())] if len(xx) else None
  out['emission_extent_pixels']=[int(xx.max()-xx.min()+1),int(yy.max()-yy.min()+1)] if len(xx) else [0,0]
  out['emission_operator']=m.get('emission_operator','not dumped')
  out['emission_energy']=m.get('emission_energy','not dumped')
  out['emission_lit_pixels_in_uv_footprint']=int((lit & mask).sum()) if lit.shape==mask.shape else 'different image dimensions; not measured'
  out['emission_note']='whole-image blob size only; not substituted for UV coverage'
 return out
def coverage_signature(surface, folder):
 m=surface['material']; fields=[surface['uv'],surface['indices'],m.get('uv_scale'),m.get('uv_offset'),m.get('repeat'),m.get('triplanar')]
 for channel in ['albedo','emission']:
  t=m.get(channel,{})
  path=folder/Path(t.get('path','missing')).name
  fields.append(hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None)
 return hashlib.sha256(json.dumps(fields,sort_keys=True).encode()).hexdigest()
def cached_coverage(name,surface,cache):
 key=(name,surface['surface'],coverage_signature(surface,ROOT))
 if key in cache and name!='RelayRack' and not (name in PALETTE and cache[key].get('brief_target')=='not assigned'):
  result=dict(cache[key]);result['reused_unchanged_uv_and_image_evidence']=True;return result
 return analyze_surface(name,surface)
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('output',type=Path,help='Directory produced by dump_scene.gd')
 parser.add_argument('--baseline',type=Path,help='Optional earlier dump and analysis; reuse identical image/UV coverage')
 args=parser.parse_args()
 ROOT=args.output
 data=json.loads((ROOT/'scene.json').read_text()); report={'scene_sha256':data['scene_sha256'],'solids':[]}
 nodes={n['name']:n for n in data['solids']}
 cache={}
 baseline=args.baseline
 if baseline and (baseline/'analysis.json').exists():
  old=json.loads((baseline/'scene.json').read_text());old_results={n['name']:n for n in json.loads((baseline/'analysis.json').read_text())['solids']}
  for n in old['solids']:
   for surface in n['surfaces']:
    cache[(n['name'],surface['surface'],coverage_signature(surface,baseline))]=old_results[n['name']]['coverage'][surface['surface']]
 for n in data['solids']:
  report['solids'].append({'name':n['name'],'valid_editable_bytes':n['kernel_deserialize_valid'],'volume':n['volume'],'editor_lock':n.get('editor_lock', 'not dumped'),'mesh_surfaces':len(n['surfaces']),
   'enabled_collision':n['collision_enabled'] and any(not c['disabled'] and c['triangles']>0 and c['layer']>0 for c in n['collision_shapes']),
   'unwrap_faces':sum(f['unwrapped'] for f in n['faces']),'total_faces':len(n['faces']),
   'coverage':[cached_coverage(n['name'],s,cache) for s in n['surfaces']]})
 stair,loft,ceiling,wall=(nodes[x] for x in ['AnnexStair','LoftDeck','Ceiling','WallE'])
 report['geometry']={'stair_top_y':stair['bounds_max'][1],'loft_top_y':loft['bounds_max'][1],
  'landing_lip_m':loft['bounds_max'][1]-stair['bounds_max'][1],
  'stair_loft_z_overlap_m':loft['bounds_max'][2]-stair['bounds_min'][2],
  'loft_headroom_m':ceiling['bounds_min'][1]-loft['bounds_max'][1],
  'east_wall_clearance_m':wall['bounds_min'][0]-stair['bounds_max'][0],
  'rack_ceiling_clearance_m':ceiling['bounds_min'][1]-nodes['RelayRack']['bounds_max'][1],
  'note':'AABB landing overlap is necessary but not sufficient; inspect highest tread corners in scene dump and rendered walk evidence.'}
 (ROOT/'analysis.json').write_text(json.dumps(report,indent=2));print(json.dumps(report['geometry'],indent=2));print('Full audit:',ROOT/'analysis.json')
