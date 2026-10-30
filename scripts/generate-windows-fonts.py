from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
output=ROOT/'assets/fonts/windows';output.mkdir(exist_ok=True)
for source,weight,style in [('Manrope',700,'Bold'),('Inter',400,'Regular'),('Inter',600,'Bold')]:
 font=TTFont(ROOT/f'assets/fonts/{source}.ttf')
 axes={'wght':weight}
 if source=='Inter':axes['opsz']=14
 font=instantiateVariableFont(font,axes,inplace=True,updateFontNames=True)
 family=f'JustVibe {source}'
 for platform,encoding,language in [(3,1,0x409),(1,0,0)]:
  for name_id,value in [(1,family),(2,style),(4,f'{family} {style}'),(6,f'JustVibe{source}-{style}'),(16,family),(17,style)]:
   font['name'].setName(value,name_id,platform,encoding,language)
 font['head'].macStyle=1 if style=='Bold' else 0
 font['OS/2'].fsSelection=(font['OS/2'].fsSelection & ~(1<<5|1<<6)) | (1<<5 if style=='Bold' else 1<<6)
 font.save(output/f'{source}-{style}.ttf')
 print(source,style,'generated')
