import struct,zlib,hashlib,sys,itertools
def zipadd(apk,dex,method=0,ver=20,dostime=0,dosdate=0,level=9,vmade=None,ext=0,align=0,flags=0):
    d=apk; e=d.rfind(b'PK\x05\x06')
    (sig,dn,dcd,n1,n,cdsize,cdoff,clen)=struct.unpack_from('<IHHHHIIH',d,e)
    head=d[:cdoff]; cd=d[cdoff:cdoff+cdsize]; comment=d[e+22:e+22+clen]
    name=b'classes.dex'; crc=zlib.crc32(dex)&0xffffffff
    if method==8:
        c=zlib.compressobj(level,zlib.DEFLATED,-15); data=c.compress(dex)+c.flush()
    else: data=dex
    off=len(head)
    extra=b''
    if align and method==0:
        pad=(-(off+30+len(name)))%align; extra=b'\0'*pad
    lh=struct.pack('<IHHHHHIIIHH',0x04034b50,ver,flags,method,dostime,dosdate,crc,len(data),len(dex),len(name),len(extra))+name+extra
    body=head+lh+data
    ch=struct.pack('<IHHHHHHIIIHHHHHII',0x02014b50,vmade if vmade is not None else ver,ver,flags,method,dostime,dosdate,crc,len(data),len(dex),len(name),0,0,0,0,ext,off)+name
    newcd=cd+ch
    eocd=struct.pack('<IHHHHIIH',0x06054b50,0,0,n1+1,n+1,len(newcd),len(body),clen)+comment
    return body+newcd+eocd
if __name__=='__main__':
    apk=open(sys.argv[1],'rb').read(); dex=open(sys.argv[2],'rb').read(); want=sys.argv[3]
    for m,v,t,lv,vm,ex,al in itertools.product([0,8],[10,20],[(0,0),(0,0x21)],[6,9],[None,0,0x314,0x0300|20],[0,0x81a40000],[0,4]):
        if m==0 and lv!=9: continue
        r=zipadd(apk,dex,m,v,t[0],t[1],lv,vm,ex,al)
        if hashlib.md5(r).hexdigest()==want: print('MATCH',m,v,t,lv,vm,hex(ex),al); break
    else: print('no match')
