"""Compare raw RGBA pixels, independent of embedded/external resource names."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from PIL import Image
def images(folder):
 data=json.loads((folder/'scene.json').read_text());result={}
 for n in data['solids']:
  for s in n['surfaces']:
   for channel in ['albedo','emission']:
    t=s['material'].get(channel,{})
    if not t.get('path'):continue
    # Baseline JSON contains its original destination; resolve by filename here.
    image=Image.open(folder/Path(t['path']).name).convert('RGBA')
    key=f"{n['name']}/surface{s['surface']}/{channel}"
    result[key]={'sha256':hashlib.sha256(image.tobytes()).hexdigest(),'size':list(image.size)}
 return data,result
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('baseline',type=Path)
 parser.add_argument('current',type=Path)
 parser.add_argument('--expected-change',action='append',default=[],help='Exact node/surface/channel key allowed to change; repeat for multiple keys')
 args=parser.parse_args()
 BASE,NOW=args.baseline,args.current
 baseline,b=images(BASE);current,c=images(NOW)
 report={'baseline_scene_sha256':baseline['scene_sha256'],'current_scene_sha256':current['scene_sha256'],'image_comparison':[],'editor_locks':[]}
 for key in sorted(b.keys()|c.keys()):
  same=b.get(key)==c.get(key)
  report['image_comparison'].append({'key':key,'same_pixels':same,'baseline':b.get(key),'current':c.get(key),'expected_change':key in args.expected_change})
 for n in current['solids']:
  if n.get('editor_lock') is not False:report['editor_locks'].append({'name':n['name'],'value':n.get('editor_lock','missing metadata dump')})
 report['all_node_editor_metadata']=current.get('editor_metadata','not dumped')
 report['unexpected_pixel_changes']=[i['key'] for i in report['image_comparison'] if not i['same_pixels'] and not i['expected_change']]
 (NOW/'baseline-comparison.json').write_text(json.dumps(report,indent=2))
 print(json.dumps({'unexpected_pixel_changes':report['unexpected_pixel_changes'],'editor_locks':report['editor_locks']},indent=2))
