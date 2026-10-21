from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import sys, subprocess, json

ROOT=Path(__file__).parent
sys.path.insert(0,str(ROOT.parent/'build-tools'))
import imageio_ffmpeg

# scene: image, section, heading, caption, duration, focus rectangle in screenshot coordinates
scenes=[
 ('01-acesso','COMECE AQUI','Do cadastro à nota autorizada','Aprenda a cadastrar o tomador e preparar sua NFS-e. Este vídeo usa dados fictícios e uma simulação em homologação.',10,None),
 ('01-acesso','ACESSO','Entre na sua empresa','Acesse nfse.veevsistemas.com. Informe o CNPJ e a senha da sua empresa e clique em Entrar na minha conta.',10,None),
 ('02-tomadores','1 · CADASTRAR TOMADOR','Abra o cadastro de clientes','No menu lateral, clique em Tomadores. Depois, clique em Cadastrar tomador.',8,(1090,129,1210,172)),
 ('03-cadastro','1 · CADASTRAR TOMADOR','Preencha o nome e o documento','Informe o nome ou a razão social e o CPF ou CNPJ do cliente. No uso real, preencha o documento correto; os zeros são apenas ilustrativos.',11,None),
 ('03-cadastro','1 · CADASTRAR TOMADOR','Confirme o cadastro','Confira os dados e clique em Cadastrar tomador para salvar o cliente.',8,None),
 ('04-cadastrado','1 · CADASTRAR TOMADOR','Cliente pronto para selecionar','O tomador aparece na lista e poderá ser selecionado nas próximas notas. Você não precisa cadastrá-lo novamente.',9,None),
 ('05-servico','2 · PREPARAR A NOTA','Abra uma Nova NFS-e','Clique em Nova NFS-e. Confira o ambiente indicado no menu: Homologação é teste; Produção gera nota com validade fiscal.',10,None),
 ('05-servico','2 · PREPARAR A NOTA','Informe o valor e o serviço','Preencha o valor do serviço e a descrição da operação. Aqui usamos R$ 250,00 e um serviço fictício.',9,None),
 ('05-servico','2 · PREPARAR A NOTA','Confira os parâmetros cadastrados','Os códigos e tributos vêm dos padrões da empresa. Use os parâmetros fiscais aprovados para o seu serviço; não copie os valores do exemplo.',11,None),
 ('06-tomador-nota','2 · PREPARAR A NOTA','Selecione o cliente cadastrado','Na seção Quem é o tomador?, desmarque Tomador não informado e selecione o cliente na lista.',10,(285,369,831,537)),
 ('06-tomador-nota','2 · PREPARAR A NOTA','Salve para revisar','Clique em Salvar e revisar. Essa ação cria o rascunho; a nota ainda não foi emitida.',8,(285,570,440,622)),
 ('07-revisao','3 · REVISAR E EMITIR','Confira todos os dados','Revise prestador, tomador, valor e descrição. Confira a data de competência antes de confirmar.',10,(365,162,915,448)),
 ('07-revisao','3 · REVISAR E EMITIR','Confirme no ambiente correto','Neste exemplo, o botão é Emitir em homologação. Em Produção, marque a confirmação da nota real e clique em Emitir nota real em produção.',12,(738,580,916,633)),
 ('08-autorizada','3 · REVISAR E EMITIR','Aguarde a autorização','Somente após o resultado Autorizada a emissão está confirmada. Se houver erro ou resultado inconclusivo, consulte a tentativa antes de repetir.',11,None),
 ('09-documentos','4 · CONSULTAR DOCUMENTOS','Localize a nota e baixe os arquivos','Clique em Ver notas fiscais. Na lista, use DANFSe para o PDF e XML para o arquivo eletrônico. Os filtros ajudam a localizar a nota.',11,(967,510,1116,549)),
 ('09-documentos','PRONTO','Seu cliente cadastrado. Sua nota organizada.','Acesse nfse.veevsistemas.com. Em caso de dúvida, fale com o suporte VEEV. Este tutorial não realizou nenhuma emissão fiscal real.',10,None)
]

W,H=1920,1080
FONT=Path('C:/Windows/Fonts')
def ft(n,b=False):return ImageFont.truetype(str(FONT/('segoeuib.ttf' if b else 'segoeui.ttf')),n)
def wrap(draw,text,font,width):
 lines=[];line=''
 for word in text.split():
  attempt=(line+' '+word).strip()
  if line and draw.textlength(attempt,font=font)>width:lines.append(line);line=word
  else:line=attempt
 if line:lines.append(line)
 return lines
def put(draw,text,x,y,size,width,color,b=False,gap=1.25):
 for line in wrap(draw,text,ft(size,b),width):draw.text((x,y),line,font=ft(size,b),fill=color);y+=round(size*gap)
 return y

frames=ROOT/'frames';frames.mkdir(exist_ok=True)
timings=[];time=0
for i,(asset,section,title,caption,duration,focus) in enumerate(scenes):
 im=Image.new('RGB',(W,H),'#f4f6ef');d=ImageDraw.Draw(im)
 d.rectangle((0,0,W,112),fill='#153f32')
 d.rounded_rectangle((36,29,91,84),radius=12,fill='#d9f08b');d.text((46,31),'W',font=ft(36,True),fill='#153f32')
 d.text((113,28),'VEEV NFS-e',font=ft(39,True),fill='white')
 d.text((1125,44),'SIMULAÇÃO · DADOS FICTÍCIOS · SEM EMISSÃO REAL',font=ft(21,True),fill='#d9f08b')
 d.rectangle((0,112,367,947),fill='#e5ecde')
 put(d,section,34,158,22,295,'#426545',True)
 put(d,title,34,230,42,298,'#173c31',True)
 d.text((34,795),f'{i+1:02d} / {len(scenes):02d}',font=ft(27,True),fill='#426545')
 put(d,'Cadastro → revisão → autorização',34,851,21,285,'#53675c')
 shot=Image.open(ROOT/'assets'/f'{asset}.png').convert('RGB')
 ow,oh=shot.size
 shot.thumbnail((1490,810),Image.Resampling.LANCZOS)
 sx=395+(1490-shot.width)//2;sy=128+(810-shot.height)//2
 # Upscale smaller captures for comfortable reading on YouTube.
 scale=min(1490/ow,810/oh);shot=Image.open(ROOT/'assets'/f'{asset}.png').convert('RGB').resize((round(ow*scale),round(oh*scale)),Image.Resampling.LANCZOS)
 sx=395+(1490-shot.width)//2;sy=128+(810-shot.height)//2
 im.paste(shot,(sx,sy))
 d=ImageDraw.Draw(im)
 d.rounded_rectangle((sx-2,sy-2,sx+shot.width+2,sy+shot.height+2),radius=4,outline='#b8cabc',width=2)
 if focus:
  # Coordinate references based on the actual captured UI. Highlight only, never change content.
  x1,y1,x2,y2=focus
  d.rounded_rectangle((sx+x1*scale-7,sy+y1*scale-7,sx+x2*scale+7,sy+y2*scale+7),radius=12,outline='#dc7e20',width=6)
 d.rectangle((0,948,W,H),fill='#0e2923')
 caplines=wrap(d,caption,ft(30),1810)
 assert len(caplines)<=3,(i,caplines)
 for n,line in enumerate(caplines):
  x=(W-d.textlength(line,font=ft(30)))//2;d.text((x,965+n*35),line,font=ft(30),fill='white')
 d.rectangle((0,H-7,int(W*(i+1)/len(scenes)),H),fill='#d9f08b')
 im.save(frames/f'{i:02d}.png')
 timings.append(dict(start=time,end=time+duration,text=caption,title=title));time+=duration

def timestamp(seconds):
 h=int(seconds//3600);m=int(seconds%3600//60);s=int(seconds%60)
 return f'{h:02d}:{m:02d}:{s:02d},000'
(ROOT/'legendas-pt-BR.srt').write_text('\n\n'.join(f'{i+1}\n{timestamp(t["start"])} --> {timestamp(t["end"])}\n{t["text"]}' for i,t in enumerate(timings))+'\n',encoding='utf-8')
(ROOT/'cenas.json').write_text(json.dumps(timings,ensure_ascii=False,indent=2),encoding='utf-8')

ff=imageio_ffmpeg.get_ffmpeg_exe();parts=[]
for i,scene in enumerate(scenes):
 out=frames/f'{i:02d}.mp4'
 subprocess.run([ff,'-y','-loglevel','error','-loop','1','-i',str(frames/f'{i:02d}.png'),'-t',str(scene[4]),'-r','24','-c:v','libx264','-preset','fast','-tune','stillimage','-crf','20','-pix_fmt','yuv420p',str(out)],check=True)
 parts.append(out)
concat=frames/'concat.txt';concat.write_text(''.join("file '"+p.name+"'\n" for p in parts),encoding='utf-8')
subprocess.run([ff,'-y','-loglevel','error','-f','concat','-safe','0','-i',str(concat),'-c','copy','-movflags','+faststart',str(ROOT/'tutorial-veev-tomador-e-nota-youtube.mp4')],check=True)

# YouTube thumbnail, only genuine demo screenshots and typography.
thumb=Image.new('RGB',(1280,720),'#153f32');dr=ImageDraw.Draw(thumb)
dr.text((45,38),'VEEV NFS-e',font=ft(37,True),fill='#d9f08b')
put(dr,'COMO FAZER\nSUA NOTA'.replace('\n',' '),45,155,77,640,'white',True)
put(dr,'1. Cadastre o tomador\n2. Emita sua NFS-e'.replace('\n',' · '),49,410,33,600,'#d9f08b',True)
shot=Image.open(ROOT/'assets/07-revisao.png').crop((340,62,940,660));shot.thumbnail((500,560));thumb.paste(shot,(740,92))
dr.text((49,638),'PASSO A PASSO COM LEGENDAS',font=ft(26,True),fill='white')
thumb.save(ROOT/'capa-youtube.jpg',quality=95)
print(f'Vídeo gerado: {time} segundos, 1920x1080. Legendas gravadas e SRT separados.')
