using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CameraController : MonoBehaviour
{
    
    public float speed = 1.0f;
    public float mouseSpeed = 100.0f;
    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        var horizontal = Input.GetAxis("Horizontal");
        var vertical = Input.GetAxis("Vertical");
        var mouse = Input.GetAxis("Mouse ScrollWheel");
        var mouseX = Input.GetAxis("Mouse X");
        var mouseY = Input.GetAxis("Mouse Y");

        transform.position += (new Vector3(horizontal * speed, vertical * speed, mouse * mouseSpeed) * Time.deltaTime);
        //transform.rotation *= Quaternion.Euler(mouseY * mouseSpeed * Time.deltaTime, mouseX * mouseSpeed * Time.deltaTime, 0);
    }
}
