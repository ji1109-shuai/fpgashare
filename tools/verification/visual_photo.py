"""Independent offline photo model, then compare with exported production RTL."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'sim/visual_upgrade_20261102_validation'
PHOTO=Path("C:/Users/ji'min'hao/xwechat_files/wxid_ddj1vy9ds87m22_ccbe/temp/RWTemp/2026-11/9e20f478899dc29eb19741386f9343c8/633ded2efe6d1d2e4866ed5cc37de878.jpg")
def model(a,s):
    if s==0:return a.copy()
    y=(a[:,:,0]+2*a[:,:,1]+a[:,:,2])//4
    pad=np.pad(y,1,mode='edge');base=np.zeros_like(y)
    for j,wy in enumerate([1,2,1]):
        for i,wx in enumerate([1,2,1]):base+=wx*wy*pad[j:j+y.shape[0],i:i+y.shape[1]]
    d=y-base//16;mag=np.maximum(abs(d)-4,0)
    if s==1:mag=mag//2
    if s==3:mag=mag+mag//2
    mag=np.minimum(mag,24);delta=np.where(d<0,-mag,mag)
    delta=np.clip(delta,-a.min(axis=2),255-a.max(axis=2))
    delta[(y<=16)|(y>=240)]=0;delta[0,:]=0;delta[-1,:]=0;delta[:,0]=0;delta[:,-1]=0
    c=a+delta[:,:,None];y=(c[:,:,0]+2*c[:,:,1]+c[:,:,2])//4
    hi,lo,den={1:(5,3,4),2:(13,3,8),3:(7,1,4)}[s]
    ye=np.where(y<64,(y*lo+den//2)//den,np.where(y<128,128-((128-y)*hi+den//2)//den,np.where(y<192,128+((y-128)*hi+den//2)//den,128+(64*hi+den//2)//den+((y-192)*lo+den//2)//den)))
    chroma=c-y[:,:,None]
    return np.clip(ye[:,:,None]+chroma+chroma//4,0,255)
def hexfile(path,a):
    path.write_text(''.join('%02x%02x%02x\n'%tuple(c) for c in a.reshape(-1,3)),encoding='ascii')
if __name__=='__main__':
    import sys
    a=np.array(Image.open(PHOTO).convert('RGB').crop((840,390,1448,678)),dtype=np.int32)
    arrays=[model(a,s) for s in range(4)]
    split=arrays[2].copy();split[:,:304]=a[:,:304];arrays.append(split)
    if '--prepare' in sys.argv:
        hexfile(E/'photo_input.hex',a)
        for s,c in enumerate(arrays):hexfile(E/f'photo_expected_{s}.hex',c)
        print('Prepared 608x288 actual-photo independent references')
    else:
        rasters=[];metrics=[]
        for s,c in enumerate(arrays):
            p=ROOT/f'sim/visual_photo_20261102_validation/photo_rtl_{s}.ppm'
            raster=Image.open(p).convert('RGB');actual=np.array(raster,dtype=np.int32)
            assert np.array_equal(c,actual),f'Photo mismatch strength {s}'
            raster.save(E/f'photo_rtl_{s}.png');rasters.append(raster)
            metrics.append({'setting':s,'changedPixels':int(np.any(c!=a,axis=2).sum()),'meanAbsoluteChannelChange':float(abs(c-a).mean())})
        sheet=Image.new('RGB',(1216,650),'#17202b');draw=ImageDraw.Draw(sheet)
        for s,label in enumerate(['DETAIL 0 / original','DETAIL 1 / mild','DETAIL 2 / default','DETAIL 3 / strong']):
            x=(s%2)*608;y=(s//2)*325;sheet.paste(rasters[s],(x,y+30));draw.text((x+12,y+9),label,fill='white')
        sheet.save(E/'photo_strength_comparison.png')
        (E/'photo_metrics.json').write_text(json.dumps({'source':str(PHOTO),'crop':[840,390,1448,678],'offlineScreenPhotoOnly':True,'rtlChecks':608*288*5,'metrics':metrics},indent=2),encoding='utf-8')
        print('Verified all 875520 photo RGB pixels and exported comparison')
