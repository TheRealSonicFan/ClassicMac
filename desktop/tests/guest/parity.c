/* Independent guest input/filesystem fixture, not shipped in the product. */
#include <Quickdraw.h>
#include <Windows.h>
#include <Fonts.h>
#include <TextEdit.h>
#include <Events.h>
#include <Files.h>
#include <Sound.h>
#include <string.h>
static WindowPtr window;
static TEHandle edit;
static char share[100]="Sharing: not mounted (Windows has no 9p backend)";
static void text(short x,short y,const char*s){Str255 p;short n=strlen(s);p[0]=n;BlockMoveData(s,p+1,n);MoveTo(x,y);DrawString(p);}
static void files(void){
 short i,volume;Str255 name;long freeBytes;FSSpec spec;short ref;char buf[64];long count;OSErr error;
 for(i=1;i<40;i++){
  if(GetVInfo(i,name,&volume,&freeBytes)!=noErr)break;
  if(name[0]==12&&!memcmp(name+1,"Shared Files",12)){
   error=FSMakeFSSpec(volume,fsRtDirID,"\phost-parity.txt",&spec);
   if(error==noErr&&FSpOpenDF(&spec,fsRdPerm,&ref)==noErr){count=sizeof(buf);error=FSRead(ref,&count,buf);FSClose(ref);
    if((error==noErr||error==eofErr)&&count>=15&&!memcmp(buf,"ClassicMac host",15)){
     FSMakeFSSpec(volume,fsRtDirID,"\pguest-parity.txt",&spec);FSpCreate(&spec,'ttxt','TEXT',smSystemScript);
     if(FSpOpenDF(&spec,fsWrPerm,&ref)==noErr){const char*out="ClassicMac guest read/write PASS\r";count=strlen(out);error=FSWrite(ref,&count,out);FSClose(ref);if(error==noErr)strcpy(share,"Sharing: host read + guest write PASS");}
    }
   }
   return;
  }
 }
}
static void draw(void){Rect r;SetPort(window);SetRect(&r,0,0,540,280);EraseRect(&r);TextFont(0);TextSize(12);text(20,25,"ClassicMac 4.1 guest parity probe");text(20,55,share);text(20,85,"Type into this native TextEdit box using Paste Text:");SetRect(&r,18,108,522,242);FrameRect(&r);TEUpdate(&r,edit);}
int main(void){Rect r,area;Str255 title="\pClassicMac Parity";EventRecord e;Boolean done=false;
 InitGraf(&qd.thePort);InitFonts();InitWindows();InitMenus();TEInit();InitDialogs(0);InitCursor();
 SetRect(&r,40,70,580,350);window=NewCWindow(0,&r,title,true,documentProc,(WindowPtr)-1,true,0);SetPort(window);
 SetRect(&area,22,112,518,238);TextFont(0);TextSize(12);edit=TENew(&area,&area);TEActivate(edit);files();SysBeep(30);draw();
 while(!done){
  if(!WaitNextEvent(everyEvent,&e,1,0)){TEIdle(edit);continue;}
  if(e.what==updateEvt){BeginUpdate(window);draw();EndUpdate(window);}
  if(e.what==keyDown||e.what==autoKey){char key=e.message&charCodeMask;if((e.modifiers&cmdKey)&&(key=='q'||key=='Q'))done=true;else if(!(e.modifiers&cmdKey))TEKey(key,edit);}
  if(e.what==mouseDown){WindowPtr hit;short part=FindWindow(e.where,&hit);if(part==inGoAway&&TrackGoAway(hit,e.where))done=true;else if(part==inContent){Point point=e.where;GlobalToLocal(&point);TEClick(point,false,edit);}else if(part==inDrag)DragWindow(hit,e.where,&qd.screenBits.bounds);}
 }
 TEDispose(edit);DisposeWindow(window);return 0;
}
