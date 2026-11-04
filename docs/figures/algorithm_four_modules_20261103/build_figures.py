from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import math, html, base64, io, json, zipfile

OUT=Path(__file__).resolve().parent
SRC=Path("C:/Users/ji'min'hao/xwechat_files/wxid_ddj1vy9ds87m22_ccbe/temp/RWTemp/2026-11/9e20f478899dc29eb19741386f9343c8")
REG='C:/Windows/Fonts/msyh.ttc'; BOLD='C:/Windows/Fonts/msyhbd.ttc'
INK='#19374F'; GRAY='#5E7182'; BLUE='#2577A4'; TEAL='#238477'; PURPLE='#7B5AA0'; ORANGE='#B96835'; LINE='#CFDBE5'
FILLS={BLUE:'#F0F7FC',TEAL:'#F0F8F5',PURPLE:'#F5F1F9',ORANGE:'#FCF4EE',GRAY:'#F4F7F9'}
CACHE={}
def font(sz,b=False):
    key=(sz,b)
    if key not in CACHE:CACHE[key]=ImageFont.truetype(BOLD if b else REG,sz)
    return CACHE[key]
class Figure:
    def __init__(self,h,title,sub):
        self.w=3000;self.h=h;self.im=Image.new('RGB',(self.w,h),'white');self.d=ImageDraw.Draw(self.im)
        self.svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="3000" height="{h}" viewBox="0 0 3000 {h}">','<rect width="100%" height="100%" fill="white"/>']
        self.text(80,38,title,62,INK,True);self.text(84,126,sub,31,GRAY)
    def text(self,x,y,t,sz=32,c=INK,b=False,center=False):
        self.d.text((x,y),t,font=font(sz,b),fill=c,anchor='mt' if center else 'lt')
        self.svg.append(f'<text x="{x}" y="{y}" font-family="Microsoft YaHei,Noto Sans CJK SC,sans-serif" font-size="{sz}" fill="{c}" font-weight="{700 if b else 400}" text-anchor="{"middle" if center else "start"}" dominant-baseline="text-before-edge">{html.escape(t)}</text>')
    def rect(self,box,fill='white',stroke=LINE,r=17,width=3):
        x,y,x1,y1=box;self.d.rounded_rectangle(box,r,fill,stroke,width)
        self.svg.append(f'<rect x="{x}" y="{y}" width="{x1-x}" height="{y1-y}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>')
    def poly(self,p,fill,stroke=None,width=3):
        self.d.polygon(p,fill=fill)
        if stroke:self.d.line(p+[p[0]],fill=stroke,width=width,joint='curve')
        self.svg.append('<polygon points="'+' '.join(f'{x},{y}' for x,y in p)+f'" fill="{fill}" stroke="{stroke or fill}" stroke-width="{width}"/>')
    def line(self,p,c=BLUE,width=5,dash=False,arrow=True):
        if not dash:self.d.line(p,fill=c,width=width,joint='curve')
        else:
            for (x,y),(x1,y1) in zip(p,p[1:]):
                L=math.hypot(x1-x,y1-y)
                if not L:continue
                for s in range(0,math.ceil(L),26):
                    z=min(s+15,L);self.d.line([(x+(x1-x)*s/L,y+(y1-y)*s/L),(x+(x1-x)*z/L,y+(y1-y)*z/L)],fill=c,width=width)
        da=' stroke-dasharray="15 11"' if dash else ''
        self.svg.append('<polyline points="'+' '.join(f'{x},{y}' for x,y in p)+f'" fill="none" stroke="{c}" stroke-width="{width}" stroke-linejoin="round"{da}/>')
        if arrow:
            x,y=p[-1];x0,y0=p[-2];L=math.hypot(x-x0,y-y0);ux=(x-x0)/L;uy=(y-y0)/L
            self.poly([(x,y),(x-ux*19-uy*9,y-uy*19+ux*9),(x-ux*19+uy*9,y-uy*19-ux*9)],c,width=1)
    def label(self,x,y,t,c=GRAY,sz=28):
        bb=self.d.textbbox((0,0),t,font=font(sz));tw=bb[2]
        self.rect((x-7,y-3,x+tw+7,y+sz+10),'white','white',0,1);self.text(x,y,t,sz,c)
    def block(self,box,title,lines=(),c=BLUE,sz=39,bs=30):
        self.rect(box,FILLS[c],c);x,y,x1,y1=box;cx=(x+x1)/2
        total=sz+(19 if lines else 0)+len(lines)*(bs+12);top=y+(y1-y-total)/2+5
        assert self.d.textbbox((0,0),title,font=font(sz,True))[2]<=x1-x-22, title
        self.text(cx,top,title,sz,INK,True,True);top+=sz+19
        for t in lines:
            assert self.d.textbbox((0,0),t,font=font(bs))[2]<=x1-x-22,t
            self.text(cx,top,t,bs,GRAY,False,True);top+=bs+12
    def diamond(self,box,lines,c=TEAL,sz=34):
        x,y,x1,y1=box;cx=(x+x1)/2;cy=(y+y1)/2
        self.poly([(cx,y),(x1,cy),(cx,y1),(x,cy)],FILLS[c],c)
        yy=cy-len(lines)*(sz+8)/2
        for t in lines:self.text(cx,yy,t,sz,INK,True,True);yy+=sz+8
    def panel(self,box,title,c=BLUE):
        self.rect(box,'#FCFDFE',LINE,22,2);self.text(box[0]+27,box[1]+22,title,35,c,True)
    def circle(self,x,y,t,c=ORANGE,r=28):
        self.d.ellipse((x-r,y-r,x+r,y+r),fill=c,outline='white',width=3)
        self.svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}" stroke="white" stroke-width="3"/>')
        self.d.text((x,y),str(t),font=font(r+9,True),fill='white',anchor='mm')
        self.svg.append(f'<text x="{x}" y="{y}" font-family="Microsoft YaHei,sans-serif" font-size="{r+9}" font-weight="700" fill="white" text-anchor="middle" dominant-baseline="central">{t}</text>')
    def paste(self,im,x,y,w):
        im=im.convert('RGB').resize((w,round(im.height*w/im.width)),Image.Resampling.LANCZOS);self.im.paste(im,(x,y))
        b=io.BytesIO();im.save(b,format='JPEG',quality=94)
        self.svg.append(f'<image x="{x}" y="{y}" width="{im.width}" height="{im.height}" href="data:image/jpeg;base64,{base64.b64encode(b.getvalue()).decode()}"/>');return im.size
    def footer(self,t):
        self.rect((70,self.h-100,2930,self.h-30),'#F2F6F9','#DCE5EC',10,2);self.text(1500,self.h-82,t,29,GRAY,False,True)
    def save(self,name):
        self.im.save(OUT/(name+'.png'),optimize=True,dpi=(300,300))
        self.im.save(OUT/(name+'.jpg'),quality=95,subsampling=0,dpi=(300,300))
        self.im.resize((1500,round(self.h/2)),Image.Resampling.LANCZOS).save(OUT/(name+'_preview.jpg'),quality=94,subsampling=0)
        (OUT/(name+'.svg')).write_text('\n'.join(self.svg+['</svg>']),encoding='utf-8')

# 1. Three actual algorithm flows: AE, AWB, display enhancement.
g=Figure(1840,'自适应成像与视觉增强','独立曝光反馈、候选中性像素白平衡与可调显示增强的处理步骤')
g.panel((60,205,1380,1680),'A  自动曝光：有效测光与收敛锁定',TEAL)
g.panel((1430,205,2170,1680),'B  自适应白平衡',BLUE)
g.panel((2220,205,2940,1680),'C  显示增强',PURPLE)
g.line([(700,395),(700,455)],TEAL)
g.line([(400,545),(405,545),(405,710)],TEAL)
g.line([(1000,545),(1050,545),(1050,710)],TEAL)
g.line([(405,915),(405,1050)],TEAL)
g.line([(120,812),(85,812),(85,425),(700,425),(700,395)],TEAL)
g.line([(1050,925),(1050,1050)],TEAL)
g.line([(1050,1235),(1050,1295),(1340,1295),(1340,425),(700,425),(700,395)],TEAL)
g.label(230,573,'是：累计稳定包',TEAL)
g.label(1035,575,'否：清零累计',TEAL,26)
g.label(430,962,'是',TEAL)
g.label(88,842,'否',TEAL)
g.block((320,285,1080,395),'AWB前亮度测量',['完整有效反馈 → AEY'],TEAL,40,31)
g.diamond((400,455,1000,635),['|AEY − 目标| ≤ 8？'],TEAL,34)
g.diamond((120,710,690,915),['连续合格反馈','达到16包？'],TEAL,33)
g.block((800,710,1300,925),'曝光优先调整',['同侧偏差连续4包后调节','曝光到边界后再补增益'],TEAL,36,28)
g.block((140,1050,670,1235),'进入LOCK状态',['保持当前曝光与增益','停止自动寄存器写入'],TEAL,36,28)
g.block((800,1050,1300,1235),'I²C更新与生效等待',['等待写入完成','丢弃生效前旧测光反馈'],TEAL,33,27)
g.block((150,1385,1290,1595),'目标可调与重新收敛',['默认AEY目标152±8；目标范围64～192，步长8','修改AUTO / LOCK目标或重新启用AUTO，可重新收敛'],GRAY,36,29)
for y0,y1 in [(405,465),(640,700),(885,955),(1360,1470)]:g.line([(1800,y0),(1800,y1)],BLUE)
g.line([(1480,795),(1450,795),(1450,1280),(1480,1280)],BLUE)
g.line([(1800,1155),(2150,1155),(2150,1410),(1800,1410),(1800,1470)],BLUE)
g.label(1815,906,'是',BLUE)
g.label(1452,906,'否',BLUE,26)
g.block((1480,285,2120,405),'RGB统计输入',['每帧搜索候选中性像素'],BLUE,36,29)
g.block((1480,465,2120,640),'样本筛选',['排除暗区、明显彩色','及过曝 / 裁剪像素'],BLUE,37,29)
g.diamond((1480,700,2120,885),['合格样本','≥1024？'],BLUE,33)
g.block((1480,955,2120,1155),'估计并平滑R/B增益',['依据G/R、G/B求补偿','采用1/4步长平滑更新'],BLUE,33,29)
g.block((1480,1200,2120,1360),'保持最近有效补偿',['尚无有效解时保持单位增益'],GRAY,32,27)
g.block((1480,1470,2120,1600),'校正RGB输出',['帧边界使用补偿参数'],BLUE,37,29)
for y0,y1 in [(405,465),(665,725),(895,955),(1125,1185),(1355,1420)]:g.line([(2580,y0),(2580,y1)],PURPLE)
g.block((2270,285,2890,405),'AWB后RGB',['仅进入显示增强支路'],PURPLE,37,29)
g.block((2270,465,2890,665),'局部细节增强',['3×3高斯基底与中心差分','NOISE软门限 · 偏移限幅'],PURPLE,37,27)
g.block((2270,725,2890,895),'亮度提取',['Y = (R + 2G + B) / 4'],PURPLE,37,28)
g.block((2270,955,2890,1125),'分段亮度S曲线',['默认：64/128/192','映射为24/128/232'],PURPLE,35,28)
g.block((2270,1185,2890,1355),'色差回加与限幅',['1.25倍原色差','RGB限制在0～255'],PURPLE,35,29)
g.block((2270,1420,2890,1600),'输出与效果对照',['DETAIL调强度 · NOISE调门限','支持原图 / 增强同帧分屏'],PURPLE,35,26)
g.footer('AE锁定后不持续追光；AWB可继续运行；显示增强不反馈测光、识别或计数。')
g.save('01_adaptive_imaging')

# 2. Recognition diagram with separate geometry and colour evidence.
g=Figure(2160,'多目标识别算法','从背景分割、几何与颜色证据，到跨批次确认和目标身份关联')
g.line([(705,390),(820,390)],PURPLE)
g.line([(1370,390),(1485,390)],PURPLE)
g.line([(2035,390),(2150,390)],PURPLE)
g.line([(2425,480),(2425,590),(805,590),(805,740)],PURPLE)
g.line([(425,480),(425,550),(2225,550),(2225,740)],TEAL,4,True)
g.line([(805,950),(805,1035),(1500,1035),(1500,1110)],PURPLE)
g.line([(2225,950),(2225,1035),(1500,1035)],TEAL)
g.line([(1500,1275),(1500,1315),(975,1315),(975,1390)],PURPLE)
g.line([(975,1600),(975,1670)],PURPLE)
g.label(1000,546,'AWB后RGB：独立颜色统计',TEAL,28)
g.label(1625,988,'几何与颜色证据联合判别',PURPLE,29)
g.block((150,300,705,480),'图像与背景统计',['AWB后RGB','亮度直方图 / 背景阈值'],PURPLE,37,28)
g.block((820,300,1370,480),'前景网格化',['8×8单元前景及颜色统计','保存空间位置关系'],PURPLE,37,28)
g.block((1485,300,2035,480),'形态学闭运算',['3×3膨胀 → 腐蚀','修补窄缺口和局部断裂'],PURPLE,37,28)
g.block((2150,300,2850,480),'连通区域与候选定位',['分离候选 · 外接框 / 面积','孔洞分析与区域质量检查'],PURPLE,36,29)
g.block((260,740,1350,950),'形状特征提取',['长宽与占用比例 · 孔洞结构 · 轮廓方向特征','识别螺丝、垫圈、六角螺母与四方螺母'],PURPLE,42,31)
g.block((1680,740,2770,950),'颜色特征判别',['HSV色相不等式 · 亮度与色度约束','按前景单元统计颜色票数；证据不足保留UNKN'],TEAL,42,30)
g.block((900,1110,2100,1275),'目标候选分类',['形成候选位置、形状与颜色；逐个提交关联'],PURPLE,42,30)
g.block((400,1390,1550,1600),'跨批次确认与身份关联',['位置、尺寸与类别约束 + 位移预测辅助匹配','维持目标ID；最多保留两次漏检的历史目标'],PURPLE,41,31)
g.block((400,1670,1550,1845),'完整目标结果发布',['位置 / 形状 / 颜色 / 身份ID / 观测与确认标记','供计数、保护和OSD使用'],PURPLE,40,30)
g.rect((110,1910,1650,2020),'#F4F7FA',LINE,12,2)
g.text(145,1928,'确认规则：形状累计确认与颜色独立确认；',30,GRAY)
g.text(145,1972,'身份重新分配使用代际标记，避免把新零件当作旧目标。',30,GRAY)
photo=ImageOps.exif_transpose(Image.open(SRC/'c3df9733e4c63684edb86e465d3077e1.jpg'))
g.paste(photo,1770,1350,1100)
g.text(2320,1998,'实拍示例：四类零件同时定位与分类',29,GRAY,False,True)
g.footer('识别消费增强前RGB；颜色采用独立证据统计；图中实拍示例保持原识别结果与状态。')
g.save('02_multi_target_recognition')

# 3. Hysteresis counting and actual batch recovery rules.
g=Figure(2250,'动态计数与批次控制','身份与方向共同约束计数，配额约束决定完成及异常处理')
g.panel((80,205,2920,720),'A  同一身份的方向越线计数示意',PURPLE)
g.rect((180,355,2820,555),'#F0F4F7','#D6E0E8',15,2)
for x,t in [(1260,'上游边界：L−H'),(1500,'计数线：L'),(1740,'下游边界：L+H')]:
    g.line([(x,315),(x,585)],PURPLE,3,True,False);g.text(x,275,t,28,PURPLE,False,True)
g.block((400,385,880,525),'同一ID：上游出现',['记录身份，建立布防'],PURPLE,32,27)
g.block((2050,385,2530,525),'同一ID：到达下游',['首次有效通过 → 计数+1'],PURPLE,32,26)
g.line([(910,455),(2015,455)],PURPLE,6)
g.text(1500,614,'跨过滞回区后只计一次；同一ID停留或重复检测不重复计数。',32,GRAY,False,True)
g.text(110,780,'B  批次状态与异常分级处理',37,PURPLE,True)
# State transitions.
g.line([(780,1000),(1100,1000)],TEAL)
g.line([(1920,1000),(2210,1000)],TEAL)
g.line([(1450,1110),(1450,1200),(445,1200),(445,1420)],ORANGE)
g.line([(1710,1110),(1710,1250),(2560,1250),(2560,1420)],ORANGE)
g.line([(780,1540),(1100,1540)],ORANGE)
g.line([(2210,1580),(1920,1580)],ORANGE)
g.line([(1510,1420),(1510,1110)],TEAL)
g.line([(1510,1670),(1510,1740),(2100,1740),(2100,1080),(2210,1080)],TEAL)
g.line([(2560,890),(2560,845),(445,845),(445,890)],TEAL,4,True)
g.label(805,940,'空场确认后可启动',TEAL,27)
g.label(1960,940,'全部配额满足',TEAL,27)
g.label(190,1138,'非需求类别 / 超额',ORANGE,28)
g.label(2070,1187,'检测溢出 / 身份歧义等',ORANGE,27)
g.label(794,1467,'连续3次新发布',ORANGE,25)
g.label(790,1502,'均未见异常类别',ORANGE,25)
g.label(1932,1450,'满足清除条件',ORANGE,25)
g.label(1958,1490,'并执行ACK',ORANGE,25)
g.label(1530,1284,'未完成且未手动STOP',TEAL,25)
g.label(1550,1702,'配额已满足 → 保持完成停车',TEAL,26)
g.label(1210,802,'NEW BATCH：清空本批与PASS，停车并重新等待清场',TEAL,26)
g.block((110,890,780,1110),'CLEAR VIEW / 待清场',['新批次不接纳原视野残留目标','空场确认前保持停车'],TEAL,36,29)
g.block((1100,890,1920,1110),'READY / RUN',['用户选择运行档位后输送','按身份与方向更新分类计数'],TEAL,41,31)
g.block((2210,890,2910,1110),'COMPLETE',['全部需求配额满足','清除运行档位，保持停车'],TEAL,39,30)
g.block((110,1420,780,1670),'NG：普通错料 / 超额',['立即停车与间歇蜂鸣','保留原档位，等待移除错误类别'],ORANGE,34,27)
g.block((1100,1420,1920,1670),'解除NG与恢复判定',['普通异常可自动解除；硬故障须确认','解除后停音，按批次及人工指令决定运行'],TEAL,36,28)
g.block((2210,1420,2910,1670),'NG：须ACK的故障',['身份、容量及检测一致性异常','清除故障后仍需显式确认'],ORANGE,35,29)
g.rect((95,1830,2905,2110),'#F4F7F9',LINE,15,2)
for y,t in [(1855,'① 配额为0的已确认类别可在上游触发NG，无需等待越线；一次或两次漏检不能解除保护。'),(1914,'② 手动选择STOP取消电机自动重启；正常完成与待清场均不触发错误蜂鸣。'),(1973,'③ 超额件移除后仅修剪本批接受数至配额，PASS累计通过数保留，供过程核对。'),(2032,'④ 图示为状态关系概括；新检测发布是恢复计数依据，等待时间本身不能证明错误件已移除。')]:g.text(130,y,t,29,GRAY)
g.footer('普通异常恢复需连续三次新的完整检测发布；硬故障还须满足清除条件并执行ACK。')
g.save('03_counting_batch_control')

# 4. Actual UI, annotated, with statistical definitions and menu flow.
g=Figure(2480,'显示交互与性能统计','真实界面标注、按键菜单处理，以及FPS与DET的统计起止事件')
photo=ImageOps.exif_transpose(Image.open(SRC/'b6f84fbe38aea5661ebbaa3f25211baa.jpg'))
px,py,pw=80,245,2050;wh=g.paste(photo,px,py,pw);ratio=pw/photo.width
regions=[(1,(332,45,730,125)),(2,(332,130,850,310)),(3,(332,315,820,395)),(4,(1985,20,2325,70)),(5,(1815,85,2330,760))]
for n,(x,y,x1,y1) in regions:
    b=(px+round(x*ratio),py+round(y*ratio),px+round(x1*ratio),py+round(y1*ratio))
    # Outline only, preserving screen pixels.
    g.d.rectangle(b,outline='#ED8C28',width=4)
    g.svg.append(f'<rect x="{b[0]}" y="{b[1]}" width="{b[2]-b[0]}" height="{b[3]-b[1]}" fill="none" stroke="#ED8C28" stroke-width="4"/>')
    bx=b[2]+34 if n!=4 else b[0]-35;by=(b[1]+b[3])/2 if n<4 else b[1]+23
    if n==5:bx=b[0]-37;by=b[1]+55
    g.circle(bx,by,n,ORANGE,26)
g.panel((2200,240,2920,1395),'界面区域说明',BLUE)
legends=[('1  成像参数',['EXP / GAIN','显示当前曝光与增益']),('2  分类与配额',['各类接受数 / 目标数 / PASS','同步展示批次进度']),('3  批次状态与帧率',['READY、COMPLETE、NG等','FPS统计ISP完整输出帧']),('4  检测耗时',['DET：识别器接受帧首','至该批全部目标结果发布']),('5  操作菜单',['显示 / 电机 / AE / AWB','配额及增强参数等配置'])]
for i,(title,lines) in enumerate(legends):
    yy=345+i*205;g.text(2235,yy,title,35,INK,True)
    for j,t in enumerate(lines):g.text(2235,yy+58+j*43,t,29,GRAY)
g.text(100,1435,'算法处理与统计流程',38,BLUE,True)
for b,title,c in [((80,1510,1010,2320),'A  菜单控制',TEAL),((1040,1510,1970,2320),'B  FPS完整帧统计',BLUE),((2000,1510,2930,2320),'C  DET识别批次计时',PURPLE)]:g.panel(b,title,c)
for cx,c in [(545,TEAL),(1505,BLUE),(2465,PURPLE)]:
    g.line([(cx,1745),(cx,1810)],c);g.line([(cx,1970),(cx,2035)],c)
g.block((130,1610,960,1745),'按键与拨码输入',['两级同步 → 消抖 → 按下事件'],TEAL,37,30)
g.block((130,1810,960,1970),'菜单状态与索引更新',['SW4开关菜单；K1 / K2选择项目'],TEAL,36,29)
g.block((130,2035,960,2195),'参数更新与动作输出',['K3 / K4减加或确认','驱动模式、配额、档位与控制请求'],TEAL,35,27)
g.text(140,2244,'参数在关闭菜单后继续保留。',29,GRAY)
g.block((1090,1610,1920,1745),'确认ISP完整输出帧',['SOF后累计172800个128位有效字'],BLUE,36,28)
g.block((1090,1810,1920,1970),'1秒统计窗口',['完成事件同步至50 MHz系统域','每满1秒发布一次整数帧率'],BLUE,36,29)
g.block((1090,2035,1920,2195),'保持数值并送显示',['显示域在帧首锁存，帧内保持','无完整帧窗口显示000'],BLUE,35,29)
g.text(1110,2244,'FPS = 窗口内完整输出帧数 / 1 s',28,GRAY)
g.block((2050,1610,2880,1745),'开始：实际接受识别帧首',['忙时未接纳的帧首不启动新计时'],PURPLE,33,28)
g.block((2050,1810,2880,1970),'内部时钟计数与换算',['按相机域时钟累计','以0.1 ms单位形成显示值'],PURPLE,36,29)
g.block((2050,2035,2880,2195),'结束：整批结果发布',['包含空场批次，结束后保持结果','异常中止时使结果失效'],PURPLE,34,28)
g.text(2070,2244,'DET = 批次发布时刻 − 接受帧首时刻',27,GRAY)
g.footer('FPS不是HDMI刷新率或检测更新率；DET不含曝光、前端ISP、跨批次确认、DDR及屏幕扫描。')
g.save('04_ui_performance')

REPORT='''# 2.3 算法与控制逻辑介绍

## 2.3.2 自适应成像与视觉增强

如图所示，系统通过独立曝光反馈与自动白平衡稳定成像，再在显示支路进行视觉增强。曝光控制使用AWB前的有效亮度反馈，以目标亮度±8为允许范围；默认目标为152，可通过菜单调整。亮度连续偏离同一侧时优先调整曝光，曝光到达边界后再补偿增益，并在寄存器更新后等待生效，避免旧测光反馈参与收敛判断。连续16个有效测光包处于允许范围后进入LOCK，保持曝光和增益；重新启用AUTO或在AUTO/LOCK下改变目标可启动新一轮调节。

白平衡在图像中筛选候选中性像素，排除暗区、明显彩色和过曝样本；合格样本不少于1024时，根据G/R、G/B估计并平滑R、B补偿，样本不足时保持最近有效补偿。显示增强采用带软噪声门限的局部细节强化，串接亮度S曲线和色差回加，突出螺纹、轮廓及明暗层次。DETAIL和NOISE分别提供强度与噪声门限调节，并支持同帧原图/增强对照。增强结果只用于显示，不反馈到曝光测光或识别分类。

配图：01_adaptive_imaging.png
建议图题：自适应成像与视觉增强算法流程。

## 2.3.3 多目标识别算法

系统以白平衡后的RGB图像为输入，根据背景亮度统计更新前景分割阈值，并在8×8网格上压缩记录前景和颜色信息。经3×3闭运算修补局部断裂后，利用连通区域分析定位目标，并提取外接框、面积及孔洞等空间特征。形状判别结合外形比例、孔洞结构与轮廓分布，区分螺丝、垫圈、六角螺母和四方螺母；颜色判别使用HSV色相不等式及亮度、色度约束，对前景颜色证据进行统计，证据不足时保留未知状态。

候选结果通过位置、尺寸、类别及位移预测辅助匹配建立跨批次身份关联，分别确认形状与颜色，并为短时漏检保留历史信息。关联身份采用槽位与代际标记区分，避免新零件沿用旧目标的计数状态。完整发布的位置、类别、身份及有效标记同时供显示、越线计数与批次保护使用。

配图：02_multi_target_recognition.png
建议图题：多目标特征识别与身份关联流程。

## 2.3.4 动态计数与批次控制

动态计数以目标身份和输送方向共同约束。目标先在计数线上游建立布防，同一身份越过下游滞回边界且尚未计数时，产生一次分类计数；目标在下游停留或被重复检测不会再次累计。系统同时检查各类目标与批次配额，配额为零的已确认类别在运行/保护相关状态下可于上游直接触发NG，无需等待越线；全部需求配额满足后进入COMPLETE并保持停车。

普通错料或超额触发停机和间歇蜂鸣，并保留原运行档位。移除异常类别后，连续三次新的完整检测结果均确认该类别不在场，才允许解除普通NG；若操作员未选择STOP且批次未完成，可按保留档位恢复。身份歧义、检测容量等故障还需满足清除条件并执行ACK。超额恢复仅修剪本批接受数量，PASS累计通过数量保留；新批次须重新经过清场，防止残留目标被当作新料计入。

配图：03_counting_batch_control.png
建议图题：身份越线计数与批次异常状态转换。

## 2.3.5 显示交互与性能统计

显示模块将实时图像与已确认目标框、类别标签、配额计数、批次状态和菜单进行OSD叠加。按键与拨码输入经同步和消抖后生成操作事件，由菜单状态机完成项目选择、数值修改和动作确认，使成像、增强、配额及电机控制参数可现场调整。

FPS在ISP输出端统计完整帧：只有帧首后累计收到172800个128位有效字，才记为一帧；完成事件同步至50 MHz系统域后，以1秒窗口发布帧率，再由显示域在帧首锁存。DET从识别器实际接受帧首开始计时，到该批全部目标结果发布结束，显示单位为0.1 ms，空场批次也参与计时。两类统计均属于旁路观察，不增加像素通路延迟；FPS不代表HDMI刷新率，DET不等同于视频端到端延迟。

配图：04_ui_performance.png
建议图题：显示界面与菜单、帧率及检测耗时统计流程。

## 图中数据与来源

图2与图4的实拍示例使用用户已提供照片，保留原画面中的识别结果、计数和性能读数，仅进行等比例排版及标注。流程图依据当前整机工程的生产实现整理，不是现场性能测量报告。工程入口为D:/fpgashare/fpgashare (4)/fpgashare/td_project/camera_to_dsi_display.al。
'''
(OUT/'四个模块介绍.md').write_text(REPORT,encoding='utf-8')
(OUT/'四个模块介绍.txt').write_text(REPORT,encoding='utf-8-sig')
(OUT/'module_descriptions.md').write_text(REPORT,encoding='utf-8')
(OUT/'module_descriptions.txt').write_text(REPORT,encoding='utf-8-sig')
# Compact preview only; individual files are the report figures.
thumbs=[]
for name in ['01_adaptive_imaging','02_multi_target_recognition','03_counting_batch_control','04_ui_performance']:
    a=Image.open(OUT/(name+'_preview.jpg'));a.thumbnail((1200,1000));thumbs.append(a)
contact=Image.new('RGB',(2480,2100),'#EAF0F4')
for i,a in enumerate(thumbs):
    x=30+(i%2)*1240+(1200-a.width)//2;y=30+(i//2)*1030;contact.paste(a,(x,y))
contact.save(OUT/'four_modules_contact_sheet.jpg',quality=93,subsampling=0)
with zipfile.ZipFile(OUT/'four_modules_report_figures.zip','w',zipfile.ZIP_DEFLATED) as z:
    for file in OUT.iterdir():
        if file.suffix in ['.png','.svg','.md','.txt']:z.write(file,file.name)
print(json.dumps({'directory':str(OUT),'files':[p.name for p in OUT.iterdir()]},ensure_ascii=False))
