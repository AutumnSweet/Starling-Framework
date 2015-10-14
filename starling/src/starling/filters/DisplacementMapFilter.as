// =================================================================================================
//
//	Starling Framework
//	Copyright 2011-2015 Gamua. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.filters
{
    import flash.display.BitmapDataChannel;
    import flash.display3D.Context3D;
    import flash.display3D.Context3DProgramType;
    import flash.display3D.Context3DTextureFormat;
    import flash.display3D.VertexBuffer3D;
    import flash.geom.Matrix3D;
    import flash.geom.Point;

    import starling.core.Starling;
    import starling.rendering.Painter;
    import starling.rendering.Program;
    import starling.rendering.VertexData;
    import starling.textures.Texture;
    import starling.utils.RenderUtil;
    import starling.utils.StringUtil;

    /** The DisplacementMapFilter class uses the pixel values from the specified texture (called
     *  the displacement map) to perform a displacement of an object. You can use this filter 
     *  to apply a warped or mottled effect to any object that inherits from the DisplayObject 
     *  class. 
     *
     *  <p>The filter uses the following formula:</p>
     *  <listing>dstPixel[x, y] = srcPixel[x + ((componentX(x, y) - 128) &#42; scaleX) / 256, 
     *                      y + ((componentY(x, y) - 128) &#42; scaleY) / 256]
     *  </listing>
     *  
     *  <p>Where <code>componentX(x, y)</code> gets the componentX property color value from the 
     *  map texture at <code>(x - mapPoint.x, y - mapPoint.y)</code>.</p>
     */
    public class DisplacementMapFilter extends FragmentFilter
    {
        private var mMapTexture:Texture;
        private var mMapPoint:Point;
        private var mComponentX:uint;
        private var mComponentY:uint;
        private var mScaleX:Number;
        private var mScaleY:Number;
        private var mRepeat:Boolean;
        
        private var mProgram:Program;
        private var mMapTexCoords:VertexData;
        private var mMapTexCoordBuffer:VertexBuffer3D;
        
        // helper objects
        private static var sOneHalf:Vector.<Number> = new <Number>[0.5, 0.5, 0.5, 0.5];
        private static var sMatrix:Matrix3D = new Matrix3D();
        private static var sMatrixData:Vector.<Number> = 
            new <Number>[0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0];
        
        /** Creates a new displacement map filter that uses the provided map texture. */
        public function DisplacementMapFilter(mapTexture:Texture, mapPoint:Point=null, 
                                              componentX:uint=0, componentY:uint=0, 
                                              scaleX:Number=0.0, scaleY:Number=0.0,
                                              repeat:Boolean=false)
        {
            mMapTexture = mapTexture;
            mMapPoint = new Point();
            mMapTexCoords = new VertexData("texCoords(float2)", 4);
            mMapTexCoords.numVertices = 4;
            mComponentX = componentX;
            mComponentY = componentY;
            mScaleX = scaleX;
            mScaleY = scaleY;
            mRepeat = repeat;
            this.mapPoint = mapPoint;
            
            super();
        }
        
        /** @inheritDoc */
        public override function dispose():void
        {
            if (mMapTexCoordBuffer) mMapTexCoordBuffer.dispose();
            super.dispose();
        }
        
        /** @private */
        protected override function createPrograms():void
        {
            // the texture coordinates for the map texture are uploaded via a separate buffer
            if (mMapTexCoordBuffer) mMapTexCoordBuffer.dispose();
            mMapTexCoordBuffer = mMapTexCoords.createVertexBuffer();
            
            var painter:Painter = Starling.painter;
            var mapFlags:String = RenderUtil.getTextureLookupFlags(
                                      mapTexture.format, mapTexture.mipMapping, mapTexture.repeat);
            var inputFlags:String = RenderUtil.getTextureLookupFlags(
                                        Context3DTextureFormat.BGRA, false, mRepeat);
            var programName:String = StringUtil.format("DMF_m{0}_i{1}", mapFlags, inputFlags);
            
            if (painter.hasProgram(programName))
            {
                mProgram = painter.getProgram(programName);
            }
            else
            {
                // vc0-3: mvpMatrix
                // va0:   vertex position
                // va1:   input texture coords
                // va2:   map texture coords
                
                var vertexShader:String = [
                    "m44  op, va0, vc0", // 4x4 matrix transform to output space
                    "mov  v0, va1",      // pass input texture coordinates to fragment program
                    "mov  v1, va2"       // pass map texture coordinates to fragment program
                ].join("\n");
                
                // v0:    input texCoords
                // v1:    map texCoords
                // fc0:   OneHalf
                // fc1-4: matrix
                
                var fragmentShader:String = [
                    "tex ft0,  v1, fs1 " + mapFlags, // read map texture
                    "sub ft1, ft0, fc0", // subtract 0.5 -> range [-0.5, 0.5]
                    "m44 ft2, ft1, fc1", // multiply matrix with displacement values
                    "add ft3,  v0, ft2", // add displacement values to texture coords
                    "tex  oc, ft3, fs0 " + inputFlags // read input texture at displaced coords
                ].join("\n");

                mProgram = Program.fromSource(vertexShader, fragmentShader);
                painter.registerProgram(programName, mProgram);
            }
        }
        
        /** @private */
        protected override function activate(pass:int, context:Context3D, texture:Texture):void
        {
            // already set by super class:
            //
            // vertex constants 0-3: mvpMatrix (3D)
            // vertex attribute 0:   vertex position (FLOAT_2)
            // vertex attribute 1:   texture coordinates (FLOAT_2)
            // texture 0:            input texture

            updateParameters(texture.nativeWidth, texture.nativeHeight);

            mProgram.activate(context);
            mMapTexCoords.setVertexBufferAttribute(mMapTexCoordBuffer, 2, "texCoords");
            context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, sOneHalf);
            context.setProgramConstantsFromMatrix(Context3DProgramType.FRAGMENT, 1, sMatrix, true);
            context.setTextureAt(1, mMapTexture.base);
        }
        
        /** @private */
        override protected function deactivate(pass:int, context:Context3D, texture:Texture):void
        {
            context.setVertexBufferAt(2, null);
            context.setTextureAt(1, null);
        }
        
        private function updateParameters(textureWidth:int, textureHeight:int):void
        {
            // matrix:
            // Maps RGBA values of map texture to UV-offsets in input texture.

            var scale:Number = Starling.contentScaleFactor;
            var columnX:int, columnY:int;

            for (var i:int=0; i<16; ++i)
                sMatrixData[i] = 0;

            if      (mComponentX == BitmapDataChannel.RED)   columnX = 0;
            else if (mComponentX == BitmapDataChannel.GREEN) columnX = 1;
            else if (mComponentX == BitmapDataChannel.BLUE)  columnX = 2;
            else                                             columnX = 3;

            if      (mComponentY == BitmapDataChannel.RED)   columnY = 0;
            else if (mComponentY == BitmapDataChannel.GREEN) columnY = 1;
            else if (mComponentY == BitmapDataChannel.BLUE)  columnY = 2;
            else                                             columnY = 3;

            sMatrixData[int(columnX * 4    )] = mScaleX * scale / textureWidth;
            sMatrixData[int(columnY * 4 + 1)] = mScaleY * scale / textureHeight;

            sMatrix.copyRawDataFrom(sMatrixData);

            // vertex buffer: (containing map texture coordinates)
            // The size of input texture and map texture may be different. We need to calculate
            // the right values for the texture coordinates at the filter vertices.

            var mapX:Number = mMapPoint.x   /  mapTexture.width;
            var mapY:Number = mMapPoint.y   /  mapTexture.height;
            var maxU:Number = textureWidth  / (mapTexture.width  * scale);
            var maxV:Number = textureHeight / (mapTexture.height * scale);

            mMapTexture.setTexCoords(mMapTexCoords, 0, "texCoords", -mapX, -mapY);
            mMapTexture.setTexCoords(mMapTexCoords, 1, "texCoords", -mapX + maxU, -mapY);
            mMapTexture.setTexCoords(mMapTexCoords, 2, "texCoords", -mapX, -mapY + maxV);
            mMapTexture.setTexCoords(mMapTexCoords, 3, "texCoords", -mapX + maxU, -mapY + maxV);

            mMapTexCoords.uploadToVertexBuffer(mMapTexCoordBuffer);
        }
        
        // properties

        /** Describes which color channel to use in the map image to displace the x result. 
         *  Possible values are constants from the BitmapDataChannel class. */
        public function get componentX():uint { return mComponentX; }
        public function set componentX(value:uint):void { mComponentX = value; }

        /** Describes which color channel to use in the map image to displace the y result. 
         *  Possible values are constants from the BitmapDataChannel class. */
        public function get componentY():uint { return mComponentY; }
        public function set componentY(value:uint):void { mComponentY = value; }

        /** The multiplier used to scale the x displacement result from the map calculation. */
        public function get scaleX():Number { return mScaleX; }
        public function set scaleX(value:Number):void { mScaleX = value; }

        /** The multiplier used to scale the y displacement result from the map calculation. */
        public function get scaleY():Number { return mScaleY; }
        public function set scaleY(value:Number):void { mScaleY = value; }
        
        /** The texture that will be used to calculate displacement. */
        public function get mapTexture():Texture { return mMapTexture; }
        public function set mapTexture(value:Texture):void
        {
            if (mMapTexture != value)
            {
                mMapTexture = value;
                createPrograms();
            }
        }
        
        /** A value that contains the offset of the upper-left corner of the target display 
         *  object from the upper-left corner of the map image. */   
        public function get mapPoint():Point { return mMapPoint; }
        public function set mapPoint(value:Point):void
        {
            if (value) mMapPoint.setTo(value.x, value.y);
            else mMapPoint.setTo(0, 0);
        }
        
        /** Indicates how the pixels at the edge of the input image (the filtered object) will
         *  be wrapped at the edge. */
        public function get repeat():Boolean { return mRepeat; }
        public function set repeat(value:Boolean):void 
        { 
            if (mRepeat != value)
            {
                mRepeat = value;
                createPrograms();
            }
        }
    }
}