;/*
;* "PS2" Application Framework
;*
;* University of Abertay Dundee
;* May be used for educational purposed only
;*
;* Author - Dr Henry S Fortuna
;*
;* $Revision: 1.2 $
;* $Date: 2007/08/19 12:45:13 $
;*
;*/

; The static (or initialisation buffer) i.e. stuff that doesn't change for each
; time this code is called.
Scales		.assign 0
LightDirs	.assign 1
LightCols	.assign 5
Transform	.assign 9 
LightTrans	.assign 13

; The input buffer (relative the the start of one of the double buffers)
NumVerts	.assign 0 
GifPacket  	.assign	1 
UVStart		.assign 2
NormStart	.assign 3
VertStart	.assign 4

; The output buffer (relative the the start of one of the double buffers)
GifPacketOut	.assign 248
UVStartOut		.assign 249
NormStartOut	.assign 250
VertStartOut	.assign 251


; Note that we have 4 data buffers: InputBuffer0, OutputBuffer0, InputBuffer1, and OutputBuffer1.
; Each buffer is 248 quad words. The different buffers are selected by reading the current offset
; from xtop (which is swapped automatically by the PS2 after each MSCALL / MSCNT).


.include "vcl_sml.i"

.init_vf_all
.init_vi_all
.syntax new

.vu

--enter
--endenter

; The START or Init code, that is only called once per frame.
START:
	fcset		0x000000

	lq			fTransform[0], Transform+0(vi00)
	lq			fTransform[1], Transform+1(vi00)
	lq			fTransform[2], Transform+2(vi00)
	lq			fTransform[3], Transform+3(vi00)
	lq			fLightTrans[0], LightTrans+0(vi00)
	lq			fLightTrans[1], LightTrans+1(vi00)
	lq			fLightTrans[2], LightTrans+2(vi00)
	lq			fLightTrans[3], LightTrans+3(vi00)
	lq			fScales, Scales(vi00)

; This begin code is called once per batch
begin:
	xtop		iDBOffset		; Load the address of the current buffer (will either be QW 16 or QW 520)
	ilw.x		iNumVerts, NumVerts(iDBOffset)
	iadd		iNumVerts, iNumVerts, iDBOffset
	iadd		Counter, vi00, iDBOffset

loop:
	lq			Vert, VertStart(Counter)				; Load the vertex from the input buffer
	mul         acc,  fTransform[0],  Vert[x]			; Transform it
    madd        acc,  fTransform[1],  Vert[y]
    madd        acc,  fTransform[2],  Vert[z]
    madd        Vert, fTransform[3],  Vert[w]
    clipw.xyz	Vert, Vert								; Clip it
	fcand		vi01, 0x3FFFF
	iaddiu		iADC, vi01, 0x7FFF
	ilw.w		iNoDraw, UVStart(Counter)				; Load the iNoDraw flag. If true we should set the ADC bit so the vert isn't drawn
	iadd		iADC, iADC, iNoDraw
	isw.w		iADC, VertStartOut(Counter)
	div         q,    vf00[w], Vert[w]			
	lq			UV,   UVStart(Counter)					; Handle the tex-coords
	mul			UV,   UV, q
	sq			UV,   UVStartOut(Counter)
	mul.xyz     Vert, Vert, q							; Scale the final vertex to fit to the screen.
	mula.xyz	acc, fScales, vf00[w]
	madd.xyz	Vert, Vert, fScales
	ftoi4.xyz	Vert, Vert
	sq.xyz		Vert, VertStartOut(Counter)				; And store in the output buffer
	lq.xyz		Norm, NormStart(Counter)				; Load the normal
	mul.xyz     acc,  fLightTrans[0],  Norm[x]			; Transform by the rotation part of the world matrix
    madd.xyz    acc,  fLightTrans[1],  Norm[y]
    madd.xyz    Norm, fLightTrans[2],  Norm[z]
    lq.xyz		fLightDirs[0], LightDirs+0(vi00)		; Load the light directions
    lq.xyz		fLightDirs[1], LightDirs+1(vi00)
    lq.xyz		fLightDirs[2], LightDirs+2(vi00)
    mula.xyz	acc, fLightDirs[0], Norm[x]				; "Transform" the normal by the light direction matrix
    madd.xyz	acc, fLightDirs[1], Norm[y]				; This has the effect of outputting a vector with all
    madd.xyz	fIntensities, fLightDirs[2], Norm[z]	; four intensities, one for each light.
    mini.xyz	fIntensities, fIntensities, vf00[w]		; Clamp the intensity to 0..1
    max.xyz		fIntensities, fIntensities, vf00[x]
    lq.xyz		fLightCols[0], LightCols+0(vi00)		; Load the light colours
    lq.xyz		fLightCols[1], LightCols+1(vi00)
    lq.xyz		fLightCols[2], LightCols+2(vi00)
    lq.xyz		fAmbient, LightCols+3(vi00)
    mula.xyz	acc, fLightCols[0], fIntensities[x]		; Transform the intensities by the light colour matrix
    madda.xyz	acc, fLightCols[1], fIntensities[y]		; This gives the final total directional light colour
    madda.xyz	acc, fLightCols[2], fIntensities[z]
    madd.xyz	fIntensities, fAmbient, vf00[w]
    loi			128										; Load 128 and put it into the alpha value
	addi.w		fIntensities, vf00, i
    ftoi0		fIntensities, fIntensities
	sq			fIntensities, NormStartOut(Counter)		; And write to the output buffer
	iaddiu		Counter, Counter, 3
	ibne		Counter, iNumVerts, loop				; Loop until all of the verts in this batch are done.
	iaddiu		iKick, iDBOffset, GifPacketOut
	lq			GP, GifPacket(iDBOffset)				; Copy the GIFTag to the output buffer
	sq			GP, GifPacketOut(iDBOffset)
	xgkick		iKick									; and render!
	
--cont
														; --cont is like end, but it really means pause, as this is where the code
														; will pick up from when MSCNT is called.
	b			begin									; Which will make it hit this code which takes it back to the start, but
														; skips the initialisation which we don't want done twice.

--exit
--endexit
