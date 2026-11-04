// Independent integer reference: rational slopes and signed floor chroma.
function integer tone_clip(input integer value);
    tone_clip=value<0 ? 0:value>255 ? 255:value;
endfunction
function [23:0] tone_reference(input [23:0] rgb,input integer amount);
    integer r,g,b,y,ye,d,hi_num,lo_num,den,rr,gg,bb;
    begin
        r=rgb[23:16];g=rgb[15:8];b=rgb[7:0];y=(r+2*g+b)/4;
        case(amount)
            1:begin hi_num=5;lo_num=3;den=4;end
            2:begin hi_num=13;lo_num=3;den=8;end
            default:begin hi_num=7;lo_num=1;den=4;end
        endcase
        if(y<64) ye=(y*lo_num+den/2)/den;
        else if(y<128) ye=128-((128-y)*hi_num+den/2)/den;
        else if(y<192) ye=128+((y-128)*hi_num+den/2)/den;
        else ye=128+(64*hi_num+den/2)/den+((y-192)*lo_num+den/2)/den;
        ye=tone_clip(ye);
        d=r-y;rr=tone_clip(ye+d+(d>>>2));
        d=g-y;gg=tone_clip(ye+d+(d>>>2));
        d=b-y;bb=tone_clip(ye+d+(d>>>2));
        tone_reference=amount==0 ? rgb:{rr[7:0],gg[7:0],bb[7:0]};
    end
endfunction
