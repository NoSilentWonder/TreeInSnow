;/*
;* "PS2" Application Framework
;*
;* University of Abertay Dundee
;* May be used for educational purposed only
;*
;* Author - Dr Henry S Fortuna
;*
;* Revised by Elinor Townsend - 2011
;* 
;*
;*/

; Buffer space available 496QW 
;
; Single particle requires:
; Input 3QW, Output 18QW - Total 21QW
;
; Input: 
;	23 particles, 3QW each - 69QW 
;	Batch size and GIFpacket - 2QW
;	
;	Total - 71QW
;	
; Output:
;	23 particle quads, 18QW each (Position, UV, Colour) - 414QW
;	GIFtag - 1QW
;	
;	Total - 415QW
;
; Input + Output = 486QW


; The static (or initialisation buffer) i.e. stuff that doesn't change for each
; time this code is called.
ViewProj		.assign 0
LocalVerts		.assign 4
UVCoords		.assign 8
CameraPos	 	.assign 12 
DefaultRight 	.assign 13
Scales			.assign 14

; The input buffer (relative the the start of one of the double buffers)
NumParticles	.assign 0 
GifPacket  		.assign	1 
InitialPosStart	.assign 2
InitVelStart 	.assign 3
AgeStart		.assign 4

; The output buffer (relative the the start of one of the double buffers)
GifPacketOut	.assign 68
UVStartOut		.assign 69
ColourStartOut	.assign 70
VertStartOut	.assign 71

; Note that we have 4 data buffers: InputBuffer0, OutputBuffer0, InputBuffer1, and OutputBuffer1.
; InputBuffer0/InputBuffer1 - 71 QWORDS
; OutputBuffer0/OutputBuffer1 - 415 QWORDS + 10QW left unused
; The different buffers are selected by reading the current offset
; from xtop (which is swapped automatically by the PS2 after each MSCALL / MSCNT).
; Offset is to switch between buffer0/buffer1, not input/output.

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
	
	MatrixLoad	fViewProj, ViewProj, vi00 				; Load the VP matrix transform into vu register
	MatrixLoad fLocalVerts, LocalVerts, vi00 			; Load the local vertices matrix into vu register
	lq fCameraPos, CameraPos(vi00) 						; Load camera position vector into vu register
	lq fDefaultRight, DefaultRight(vi00) 				; Load default right vector into vu register
	lq fScales, Scales(vi00) 							; Load scales vector into vu register
	
; This begin code is called once per batch
begin:
	xtop		iDBOffset								; Load the address of the current buffer (will either be QW 32 or QW 536)
	ilw.x		iNumParticles, NumParticles(iDBOffset)
	iadd		iNumParticles, iNumParticles, iDBOffset	
	iadd		CounterIn, vi00, iDBOffset	
	iadd		CounterOut, vi00, iDBOffset	

; In batch loop	
loop:
	lq			InitPos, InitialPosStart(CounterIn)		; Load the initial position from the input buffer
	lq 			InitVel, InitVelStart(CounterIn)		; Load the velocity from the input buffer
	lq			Age, AgeStart(CounterIn)				; Load the age from the input buffer
	
	; Use constant acceleration equation to update particle position
	; Position = 0.5*acceleration*time^2 + initialVel*time + initialPos
	; Age.xyz = 0.5*acceleration*time^2
	; Age.w = time
	mul			Velocity, InitVel, vf00					; Create some temporary vectors
	mul			tempVec, InitVel, vf00
	
	mul.xyz		Velocity, InitVel, Age[w]				; Velocity = InitVel*time
	add.xyz		tempVec, Velocity, Age					; tempVec = Velocity + 0.5*time^2*acceleration
	add			Position, tempVec, InitPos				; Position = InitPos + tempVec

	; Create WVP matrix
	sub.xyz				Look, fCameraPos, Position		; Find Look vector by subtracting particle position from camera position
	VectorNormalize   	Look, Look
	
	opmula.xyz     		ACC, fDefaultRight, Look		; Find Right vector by finding cross product of Look and default right (0, 1, 0)
	opmsub.xyz     		Right, Look, fDefaultRight
	sub.w          		Right, vf00, vf00
	VectorNormalize		Right, Right
	
	opmula.xyz     		ACC, Look, Right				; Find Up vector by finding cross product of Look and Right
	opmsub.xyz     		Up, Right, Look
	sub.w          		Up, vf00, vf00
	
	VectorAdd	W[0], Right, vf00						; Create W matrix using Right, Up, Look and Position of particle
	VectorAdd	W[1], Up, vf00
	VectorAdd	W[2], Look, vf00
	VectorAdd	W[3], Position, vf00
	
	sub			W[0], W[0], vf00
	sub			W[1], W[1], vf00
	sub			W[2], W[2], vf00

	MatrixMultiply WVP, W, fViewProj					; Multiply W with ViewProjection matrix to create WVP

	; Translate particle vertices to correct positions
	MatrixMultiplyVertex TrueVerts[0], WVP, fLocalVerts[0]
	MatrixMultiplyVertex TrueVerts[1], WVP, fLocalVerts[1]
	MatrixMultiplyVertex TrueVerts[2], WVP, fLocalVerts[2]
	MatrixMultiplyVertex TrueVerts[3], WVP, fLocalVerts[3]
		
	; Vertex 1
	clipw.xyz	TrueVerts[0], TrueVerts[0]				; Clip it
	fcand		vi01, 0x3FFFF
	iaddiu		iADC, vi01, 0x7FFF
	isw.w		iADC, VertStartOut(CounterOut)
	div         q,    vf00[w], TrueVerts[0][w]			
	lq			UV,   UVCoords(CounterOut)				; Handle the tex-coords
	mul			UV,   UV, q
	sq			UV,   UVStartOut(CounterOut)
	div         q,    vf00[w], TrueVerts[0][w]
	mul.xyz     TrueVerts[0], TrueVerts[0], q			; Scale the final vertex to fit to the screen.
	mula.xyz	acc, fScales, vf00[w]
	madd.xyz	TrueVerts[0], TrueVerts[0], fScales
	ftoi4.xyz 	TrueVerts[0], TrueVerts[0]
	sq.xyz		TrueVerts[0], VertStartOut(CounterOut)	; And store in the output buffer
	loi			128
	addi.xyzw	colour, vf00, i
	ftoi0		colour, colour
	sq			colour, ColourStartOut(CounterOut)
	
	; Vertex 2 and 4
	clipw.xyz	TrueVerts[1], TrueVerts[1]				; Clip it
	fcand		vi01, 0x3FFFF
	iaddiu		iADC, vi01, 0x7FFF
	isw.w		iADC, VertStartOut+3(CounterOut)
	isw.w		iADC, VertStartOut+9(CounterOut)
	div         q,    vf00[w], TrueVerts[1][w]
	lq			UV,   UVCoords+1(vi00)					; Handle the tex-coords				
	mul			UV,   UV, q
	sq			UV,   UVStartOut+3(CounterOut)
	sq			UV,   UVStartOut+9(CounterOut)
	div         q,    vf00[w], TrueVerts[1][w]
	mul.xyz     TrueVerts[1], TrueVerts[1], q			; Scale the final vertex to fit to the screen.
	mula.xyz	acc, fScales, vf00[w]
	madd.xyz	TrueVerts[1], TrueVerts[1], fScales
	ftoi4.xyz 	TrueVerts[1], TrueVerts[1]
	sq.xyz		TrueVerts[1], VertStartOut+3(CounterOut); And store in the output buffer
	sq.xyz		TrueVerts[1], VertStartOut+9(CounterOut); And store in the output buffer
	loi			128
	addi.xyzw	colour, vf00, i
	ftoi0		colour, colour
	sq			colour, ColourStartOut+3(CounterOut)
	sq			colour, ColourStartOut+9(CounterOut)
	
	; Vertex 3 and 5
	clipw.xyz	TrueVerts[2], TrueVerts[2]				; Clip it
	fcand		vi01, 0x3FFFF
	iaddiu		iADC, vi01, 0x7FFF
	isw.w		iADC, VertStartOut+6(CounterOut)
	isw.w		iADC, VertStartOut+12(CounterOut)
	div         q,    vf00[w], TrueVerts[2][w]
	lq			UV,   UVCoords+2(vi00)					; Handle the tex-coords				
	mul			UV,   UV, q
	sq			UV,   UVStartOut+6(CounterOut)
	sq			UV,   UVStartOut+12(CounterOut)
	div         q,    vf00[w], TrueVerts[2][w]
	mul.xyz     TrueVerts[2], TrueVerts[2], q			; Scale the final vertex to fit to the screen.
	mula.xyz	acc, fScales, vf00[w]
	madd.xyz	TrueVerts[2], TrueVerts[2], fScales
	ftoi4.xyz TrueVerts[2], TrueVerts[2]
	sq.xyz		TrueVerts[2], VertStartOut+6(CounterOut); And store in the output buffer
	sq.xyz		TrueVerts[2], VertStartOut+12(CounterOut); And store in the output buffer
	loi			128
	addi.xyzw	colour, vf00, i
	ftoi0		colour, colour
	sq			colour, ColourStartOut+6(CounterOut)
	sq			colour, ColourStartOut+12(CounterOut)
	
	; Vertex 6
	clipw.xyz	TrueVerts[3], TrueVerts[3]				; Clip it
	fcand		vi01, 0x3FFFF
	iaddiu		iADC, vi01, 0x7FFF
	isw.w		iADC, VertStartOut+15(CounterOut)
	div         q,    vf00[w], TrueVerts[3][w]	
	lq			UV,   UVCoords+3(vi00)					; Handle the tex-coords			
	mul			UV,   UV, q
	sq			UV,   UVStartOut+15(CounterOut)
	div         q,    vf00[w], TrueVerts[3][w]
	mul.xyz     TrueVerts[3], TrueVerts[3], q			; Scale the final vertex to fit to the screen.
	mula.xyz	acc, fScales, vf00[w]
	madd.xyz	TrueVerts[3], TrueVerts[3], fScales
	ftoi4.xyz 	TrueVerts[3], TrueVerts[3]
	sq.xyz		TrueVerts[3], VertStartOut+15(CounterOut); And store in the output buffer
	loi			128
	addi.xyzw	colour, vf00, i
	ftoi0		colour, colour
	sq			colour, ColourStartOut+15(CounterOut)

	iaddiu		CounterIn, CounterIn, 3
	iaddiu		CounterOut, CounterOut, 18
	ibne		CounterIn, iNumParticles, loop			; Loop until all of the verts in this batch are done.
	lq			GIF, GifPacket(iDBOffset)				; Copy the GIFTag to the output buffer
	sq			GIF, GifPacketOut(iDBOffset)
	iaddiu		iKick, iDBOffset, GifPacketOut
	xgkick		iKick									; and render!
	
--cont
														; --cont is like end, but it really means pause, as this is where the code
														; will pick up from when MSCNT is called.
	b			begin									; Which will make it hit this code which takes it back to the start, but
														; skips the initialisation which we don't want done twice.

--exit
--endexit
