// =================================================================================================
//
//	Starling Framework
//	Copyright 2011 Gamua OG. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.textures
{
    import flash.display3D.textures.TextureBase;
    import flash.geom.Rectangle;
    
    import starling.core.RenderSupport;
    import starling.core.Starling;
    import starling.display.DisplayObject;
    import starling.display.Image;
    import starling.utils.VertexData;
    import starling.utils.getNextPowerOfTwo;

    /** A RenderTexture is a dynamic texture onto which you can draw any display object.
     * 
     *  <p>After creating a render texture, just call the <code>drawObject</code> method to render 
     *  an object directly onto the texture. The object will be drawn onto the texture at its current
     *  position, adhering its current rotation, scale and alpha properties.</p> 
     *  
     *  <p>Drawing is done very efficiently, as it is happening directly in graphics memory. After 
     *  you have drawn objects onto the texture, the performance will be just like that of a normal 
     *  texture - no matter how many objects you have drawn.</p>
     *  
     *  <p>If you draw lots of objects at once, it is recommended to bundle the drawing calls in 
     *  a block via the <code>drawBundled</code> method, like shown below. That will speed it up 
     *  immensely, allowing you to draw hundreds of objects very quickly.</p>
     *  
     * 	<pre>
     *  renderTexture.drawBundled(function():void
     *  {
     *     for (var i:int=0; i&lt;numDrawings; ++i)
     *     {
     *         image.rotation = (2 &#42; Math.PI / numDrawings) &#42; i;
     *         renderTexture.draw(image);
     *     }   
     *  });
     *  </pre>
     *     
     */
    public class RenderTexture extends Texture
    {
        private var mActiveTexture:Texture;
        private var mBufferTexture:Texture;
        private var mHelperImage:Image;
        private var mDrawing:Boolean;
        
        private var mNativeWidth:int;
        private var mNativeHeight:int;
        private var mSupport:RenderSupport;
        
        /** Creates a new RenderTexture with a certain size. If the texture is persistent, the
         *  contents of the texture remains intact after each draw call, allowing you to use the
         *  texture just like a canvas. If it is not, it will be cleared before each draw call.
         *  Persistancy doubles the required graphics memory! Thus, if you need the texture only 
         *  for one draw (or drawBundled) call, you should deactivate it. */
        public function RenderTexture(width:int, height:int, persistent:Boolean=true)
        {
            mSupport = new RenderSupport();
            mNativeWidth  = getNextPowerOfTwo(width);
            mNativeHeight = getNextPowerOfTwo(height);
            mActiveTexture = Texture.empty(width, height, 0x0, true);
            
            if (persistent)
            {
                mBufferTexture = Texture.empty(width, height, 0x0, true);
                mHelperImage = new Image(mBufferTexture);
            }
        }
        
        /** @inheritDoc */
        public override function dispose():void
        {
            mActiveTexture.dispose();
            
            if (isPersistent) 
            {
                mBufferTexture.dispose();
                mHelperImage.dispose();
            }
            
            super.dispose();
        }
        
        /** Draws an object onto the texture, adhering its properties for position, scale, rotation 
         *  and alpha. */
        public function draw(object:DisplayObject, antiAliasing:int=0):void
        {
            if (object == null) return;
            
            if (mDrawing)
                render();
            else
                drawBundled(render, antiAliasing);
            
            function render():void
            {
                mSupport.pushMatrix();
                mSupport.transformMatrix(object);            
                object.render(mSupport, 1.0);
                mSupport.popMatrix();
            }
        }
        
        /** Bundles several calls to <code>draw</code> together in a block. This avoids buffer 
         *  switches and allows you to draw multiple objects into a non-persistent texture. */
        public function drawBundled(drawingBlock:Function, antiAliasing:int=0):void
        {
            // limit drawing to relevant area
            Starling.context.setScissorRectangle(
                new Rectangle(0, 0, mActiveTexture.width, mActiveTexture.height));
            
            // persistent drawing uses double buffering, as Molehill forces us to call 'clear'
            // on every render target once per update.
            
            // switch buffers
            if (isPersistent)
            {
                var tmpTexture:Texture = mActiveTexture;
                mActiveTexture = mBufferTexture;
                mBufferTexture = tmpTexture;
                mHelperImage.texture = mBufferTexture;
            }
            
            Starling.context.setRenderToTexture(mActiveTexture.base, false, antiAliasing);
            
            mSupport.setOrthographicProjection(mNativeWidth, mNativeHeight);
            mSupport.setDefaultBlendFactors(true);
            mSupport.clear();
            
            // draw buffer
            if (isPersistent)
                mHelperImage.render(mSupport, 1.0);
                        
            try
            {
                mDrawing = true;
                
                // draw new objects
                if (drawingBlock != null)
                    drawingBlock();
            }
            finally
            { 
                mDrawing = false;
                mSupport.resetMatrix();
                Starling.context.setScissorRectangle(null);
                Starling.context.setRenderToBackBuffer();
            }
        }
        
        /** Clears the texture (restoring full transparency). */
        public function clear():void
        {
            Starling.context.setRenderToTexture(mActiveTexture.base);
            mSupport.clear();

            if (isPersistent)
            {
                Starling.context.setRenderToTexture(mActiveTexture.base);
                mSupport.clear();
            }
            
            Starling.context.setRenderToBackBuffer();
        }
        
        /** @inheritDoc */
        public override function adjustVertexData(vertexData:VertexData, vertexID:int, count:int):void
        {
            return mActiveTexture.adjustVertexData(vertexData, vertexID, count);   
        }
        
        /** Indicates if the texture is persistent over multiple draw calls. */
        public function get isPersistent():Boolean { return mBufferTexture != null; }
        
        /** @inheritDoc */
        public override function get width():Number { return mActiveTexture.width; }        
        
        /** @inheritDoc */
        public override function get height():Number { return mActiveTexture.height; }        
        
        /** @inheritDoc */
        public override function get premultipliedAlpha():Boolean 
        { 
            return mActiveTexture.premultipliedAlpha; 
        }
        
        /** @inheritDoc */
        public override function get base():TextureBase 
        { 
            return mActiveTexture.base; 
        }
    }
}