BITS 16
section .text
foo:
seto ah
setno [eax+esi*1]
setb ah
setc [eax+esi*1]
setnae ah
setnb [eax+esi*1]
setnc ah
setae [eax+esi*1]
sete ah
setz [eax+esi*1]
setne ah
setnz [eax+esi*1]
setbe ah
setna [eax+esi*1]
seta ah
setnbe [eax+esi*1]
sets ah
setns [eax+esi*1]
setp ah
setpe [eax+esi*1]
setnp ah
setpo [eax+esi*1]
setl ah
setnge [eax+esi*1]
setge ah
setnl [eax+esi*1]
setle ah
setng [eax+esi*1]
setnle ah
setg [eax+esi*1]
