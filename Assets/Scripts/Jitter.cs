
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace TAA
{
    internal static class Jitter
    {
        internal static float GetHalton(int index, int radix)
        {
            var result = 0f;
            var fraction = 1f / radix;
            while (index > 0)
            {
                result += (index % radix) * fraction;
                index /= radix;
                fraction /= radix;
            }

            return result;
        }

        internal static Vector2 CalculateJitter(int frameIndex)
        {
            var jitterX = GetHalton((frameIndex & 1023) + 1, 2) - 0.5f;
            var jitterY = GetHalton((frameIndex & 1023) + 1, 3) - 0.5f;
            return new Vector2(jitterX, jitterY);
        }

        internal static Matrix4x4 CalculateJitterProjectionMatrix(ref CameraData cameraData, float jitterScale = 1f)
        {
            var projectionMatrix = cameraData.GetProjectionMatrix();
            var frameIndex = Time.frameCount;

            var width = cameraData.camera.pixelWidth;
            var height = cameraData.camera.pixelHeight;

            var jitter = CalculateJitter(frameIndex) * jitterScale;

            projectionMatrix.m02 += jitter.x;
            projectionMatrix.m12 += jitter.y;

            return projectionMatrix;
        }
    }
}

