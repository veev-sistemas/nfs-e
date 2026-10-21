from pathlib import Path
import base64, json, subprocess, sys, textwrap
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).parent
sys.path.insert(0,str(ROOT/'build-tools'))
import imageio_ffmpeg

slides=[
 ('painel','Sua rotina fiscal, mais simples.','Conheça o VEEV NFS-e: organize notas de serviço em um só lugar.','Uma visão da sua empresa','Acompanhe notas disponíveis, valores e rascunhos no painel.'),
 ('acesso','Cada empresa tem seu acesso.','Entre com CNPJ e senha para acessar as informações da sua empresa.','Acesso da empresa','O acesso é individualizado por empresa. O administrador gerencia a liberação de uso.'),
 ('tomadores','Seus clientes, organizados.','Cadastre os tomadores e reutilize os dados nas próximas notas.','Cadastro de tomadores','Mantenha pessoas e empresas cadastradas para selecionar durante a preparação da nota.'),
 ('emissao','Prepare. Revise. Confirme.','Informe o serviço e o valor. Confira os dados antes de emitir.','Preparação da nota','Os padrões cadastrados já aparecem preenchidos. Salve um rascunho e revise antes de confirmar a emissão.'),
 ('notas','Encontre a nota que precisa.','Consulte por período e situação. Acesse o XML e o DANFSe.','Consulta e documentos','Filtre por data e situação ou busque a nota. As notas autorizadas têm opções para baixar XML e DANFSe.'),
 ('configuracoes','Menos preenchimento repetido.','Configure os padrões de serviço para os próximos rascunhos.','Padrões do serviço','Defina os padrões que serão usados nos novos rascunhos. O ambiente e o certificado são gerenciados pelo administrador.'),
 ('painel','Vamos simplificar sua rotina?','Fale com a VEEV Sistemas e agende uma demonstração.','Conheça na prática','Apresente a rotina da sua empresa e conheça os recursos em uma demonstração acompanhada.')]

data=[]
for key,title,subtitle,heading,copy in slides:
 b64=base64.b64encode((ROOT/'assets'/f'{key}.png').read_bytes()).decode()
 data.append(dict(title=heading,copy=copy,image='data:image/png;base64,'+b64))

html='''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VEEV NFS-e · Demonstração</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f3f5ef;color:#173c31;font-family:Segoe UI,Arial,sans-serif}header{padding:20px 4vw;background:#153f32;color:white;display:flex;justify-content:space-between;align-items:center;gap:20px}header strong{font-size:25px;letter-spacing:2px}header span{font-size:12px;color:#d9f08b}main{max-width:1500px;margin:auto;padding:30px 4vw}.intro{display:flex;justify-content:space-between;gap:20px;align-items:center}h1{font-size:clamp(25px,3vw,42px);letter-spacing:-1px;margin:0 0 12px}p{font-size:17px;line-height:1.55;max-width:780px;margin:0 0 20px;color:#53675c}.step{color:#517b4b;font-size:12px;letter-spacing:2px;margin-bottom:12px}.screen{display:block;width:100%;max-height:62vh;object-fit:contain;background:white;border-radius:14px;border:1px solid #cbd8ce;cursor:zoom-in;box-shadow:0 16px 50px #153f3214}.controls{display:flex;align-items:center;justify-content:space-between;gap:14px;margin:22px 0;flex-wrap:wrap}button{font:inherit;cursor:pointer;border:1px solid #c1d2c4;background:white;color:#173c31;border-radius:8px;padding:12px 18px}button:hover{background:#e4eddd}button:focus-visible{outline:3px solid #6c994b;outline-offset:3px}button:disabled{opacity:.45;cursor:default}.primary{background:#145c43;color:white;border-color:#145c43}.dots{display:flex;gap:8px;flex-wrap:wrap}.dots button{padding:9px 13px}.dots button[aria-current=true]{background:#d9f08b;border-color:#9bbb66}.note{font-size:12px;color:#65776c}dialog{max-width:96vw;width:1400px;max-height:96vh;border:0;border-radius:12px;padding:16px;background:#f3f5ef}dialog::backdrop{background:#082c26bb}dialog img{width:100%;display:block}dialog button{margin-bottom:10px}@media(max-width:650px){header{align-items:start;flex-direction:column;gap:5px}.intro{display:block}.screen{max-height:none}.dots{order:3;width:100%}main{padding:22px 16px}p{font-size:15px}}</style>
<header><strong>VEEV <small style="font-size:14px;letter-spacing:0">NFS-e</small></strong><span>Demonstração com dados fictícios · sem emissão real</span></header>
<main><div class="step" id="step"></div><div class="intro"><div><h1 id="title"></h1><p id="copy"></p></div><button id="auto">▶ Apresentação automática</button></div><img class="screen" id="screen" alt="Tela do sistema VEEV NFS-e" title="Clique para ampliar"><div class="controls"><button id="prev">← Anterior</button><nav class="dots" id="dots" aria-label="Etapas da apresentação"></nav><button class="primary" id="next">Próximo →</button></div><p class="note">Tour guiado: use as setas do teclado para navegar. Clique na tela para ampliar. Os botões mostrados dentro das imagens são ilustrativos.</p></main>
<dialog id="zoom"><button id="close">Fechar ampliação</button><img id="large" alt="Tela ampliada do sistema"></dialog>
<script>const slides=DATA;let index=0,timer=null;const $=id=>document.getElementById(id);function render(){const s=slides[index];$('title').textContent=s.title;$('copy').textContent=s.copy;$('step').textContent='CONHEÇA O SISTEMA · '+(index+1)+' / '+slides.length;$('screen').src=s.image;$('large').src=s.image;$('prev').disabled=index===0;$('next').textContent=index===slides.length-1?'Recomeçar ↺':'Próximo →';$('dots').replaceChildren(...slides.map((s,i)=>{let b=document.createElement('button');b.textContent=i+1;b.setAttribute('aria-label',s.title);b.setAttribute('aria-current',String(i===index));b.onclick=()=>{stop();index=i;render()};return b}));}function stop(){clearInterval(timer);timer=null;$('auto').textContent='▶ Apresentação automática'}function next(){index=(index+1)%slides.length;render()}$('prev').onclick=()=>{stop();index=Math.max(0,index-1);render()};$('next').onclick=()=>{stop();next()};$('auto').onclick=()=>{if(timer){stop();return}$('auto').textContent='Ⅱ Pausar apresentação';timer=setInterval(next,9000)};$('screen').onclick=()=>{$('zoom').showModal()};$('close').onclick=()=>$('zoom').close();document.addEventListener('keydown',e=>{if($('zoom').open)return;if(e.key==='ArrowRight'){$('next').click()}if(e.key==='ArrowLeft'){$('prev').click()}});render();</script></html>'''
(ROOT/'demonstracao-veev.html').write_text(html.replace('DATA',json.dumps(data,ensure_ascii=False)),encoding='utf-8')

W,H=720,1280
fontpath=Path('C:/Windows/Fonts')
def font(n,bold=False): return ImageFont.truetype(str(fontpath/('segoeuib.ttf' if bold else 'segoeui.ttf')),n)
def lines(draw,text,x,y,size,width,color,bold=False):
 f=font(size,bold); words=text.split(); line=''
 for word in words+['\n']:
  candidate=(line+' '+word).strip()
  if word=='\n' or draw.textlength(candidate,font=f)>width:
   draw.text((x,y),line,font=f,fill=color);y+=int(size*1.35);line='' if word=='\n' else word
  else:line=candidate
 return y

frames=ROOT/'frames';frames.mkdir(exist_ok=True)
for i,(key,title,subtitle,_,__) in enumerate(slides):
 im=Image.new('RGB',(W,H),'#123f32');d=ImageDraw.Draw(im)
 d.rounded_rectangle((42,46,96,100),radius=14,fill='#d9f08b');d.text((52,50),'W',font=font(34,True),fill='#173c31')
 d.text((114,49),'VEEV',font=font(38,True),fill='white');d.text((114,98),'NFS-e Nacional',font=font(20),fill='#c6d9cf')
 d.text((44,172),f'CONHEÇA O SISTEMA   {i+1:02d} / 07',font=font(17,True),fill='#d9f08b')
 lines(d,title,44,225,48,630,'white',True)
 shot=Image.open(ROOT/'assets'/f'{key}.png').convert('RGB')
 # Focus on the working area on vertical screens; keep access screen intact.
 if key!='acesso':shot=shot.crop((225,0,shot.width,shot.height))
 shot.thumbnail((630,490))
 x=(W-shot.width)//2;y=460+(490-shot.height)//2
 d.rounded_rectangle((36,448,684,970),radius=18,fill='#f5f7f2')
 im.paste(shot,(x,y))
 lines(d,subtitle,44,1010,29,630,'#e5eee7')
 d.line((44,1170,676,1170),fill='#477460',width=1)
 d.text((44,1190),'Demonstração com dados fictícios',font=font(18),fill='#c6d9cf')
 d.text((44,1220),'Sem emissão de nota real',font=font(16),fill='#c6d9cf')
 im.save(frames/f'{i:02d}.png')

ff=imageio_ffmpeg.get_ffmpeg_exe()
# 7 scenes of 9 seconds, subtle zoom, H.264 for sharing on WhatsApp.
parts=[]
for i in range(len(slides)):
 out=frames/f'{i:02d}.mp4'
 subprocess.run([ff,'-y','-loglevel','error','-loop','1','-i',str(frames/f'{i:02d}.png'),'-t','9','-vf',"scale=736:1308,crop=720:1280:x='8+4*sin(t/3)':y='14+5*sin(t/3)',fps=24,format=yuv420p",'-c:v','libx264','-preset','fast','-crf','22',str(out)],check=True)
 parts.append(out)
manifest=frames/'concat.txt';manifest.write_text(''.join("file '"+p.name+"'\n" for p in parts),encoding='utf-8')
subprocess.run([ff,'-y','-loglevel','error','-f','concat','-safe','0','-i',str(manifest),'-c','copy','-movflags','+faststart',str(ROOT/'veev-nfse-whatsapp.mp4')],check=True)
print('Tour e vídeo gerados com sucesso.')
