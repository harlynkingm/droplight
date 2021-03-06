//
//  PictureViewController.swift
//  Droplight
//
//  Created by MHK on 11/12/16.
//  Copyright © 2016 MHK. All rights reserved.
//

import UIKit
import AVFoundation
import Alamofire

/**
 Allows the user to see a picture they've taken and upload it to the server
 */
class PictureViewController: UIViewController, LocationControllerDelegate, UITextFieldDelegate {
    
    // MARK: - Initializers
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var uploadButton: UIButton!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var saveButton: UIButton!
    @IBOutlet weak var locationButton: UIButton!
    @IBOutlet weak var textButton: UIButton!
    @IBOutlet weak var locationText: UILabel!
    @IBOutlet weak var locationBg: UIView!
    @IBOutlet weak var loading: UIActivityIndicatorView!
    @IBOutlet weak var caption: UITextField!
    
    var currentImage : UIImage?
    
    var effects : EffectsController = DataController.sharedData.effects
    var userLocation : LocationController? = DataController.sharedData.userLocation
    var browserImages : ImageLoader? = DataController.sharedData.browserImages
    var collectionImages : ImageLoader? = DataController.sharedData.collectionImages
    
    var locationSharing : Bool = true
    var isWaitingForLocation : Bool = false
    var didUpload : Bool = false
    var captionBottom: CGFloat = CGFloat(0)
    
    // MARK: - Setup Functions
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        userLocation?.delegate = self
        caption.delegate = self
        updateLocationText()
        setupGestures()
        registerForKeyboardNotifications()
    }
    
    func setupGestures(){
        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapBackground))
        self.view.addGestureRecognizer(tap)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        effects.addDefaultShadow(view: uploadButton)
        effects.addDefaultShadow(view: closeButton)
        effects.addDefaultShadow(view: saveButton)
        effects.addDefaultShadow(view: locationButton)
        effects.addDefaultShadow(view: textButton)
        caption.layer.cornerRadius = caption.bounds.height/2
        locationBg.layer.cornerRadius = locationBg.bounds.height/2
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        deregisterFromKeyboardNotifications()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.loading.stopAnimating()
        updateImage()
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    /**
     Passes forward the variable that says whether an image was uploaded
     */
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? CameraViewController {
            destination.didUpload = didUpload
        }
    }
    
    // MARK: - View Updating Functions
    
    /**
     Updates the background of the picture view to display the current image
     */
    func updateImage() {
        if let image : UIImage = currentImage {
            imageView.image = image
        }
    }
    
    /**
     Delegate function that is called when new location data is retrieved
     */
    func didGetLocation(sender: LocationController) {
        updateLocationText()
    }
    
    /**
     Updates the text of the location using the Geocoder data of the placemark
     */
    func updateLocationText() {
        if let location = userLocation {
            if let placemark = location.placemark {
                if let sublocality = placemark.subLocality {
                    locationText.text = sublocality + ", " + placemark.locality!
                } else {
                    locationText.text = placemark.locality! + ", " + placemark.administrativeArea!
                }
            }
            if (isWaitingForLocation){
                isWaitingForLocation = false
                asyncUpload()
            }
        }
    }
    
    // MARK: - User Actions
    
    /**
     Saves an image to the device locally
     */
    @IBAction func saveImage() {
        if let image : UIImage = currentImage {
            self.loading.startAnimating()
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(imageSaved(_:didFinishSavingWithError: contextInfo:)), nil)
        }
    }
    
    /**
     Callback function to be called once an image is saved to the local device
     */
    func imageSaved(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {
        self.loading.stopAnimating()
        if let error = error {
            let ac = UIAlertController(title: "Save error", message: error.localizedDescription, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        } else {
            saveButton.setImage(UIImage(named: "check"), for: UIControlState.normal)
        }
    }
    
    /**
     Toggles location to appear/disappear when the location button is pressed
     */
    @IBAction func toggleLocation() {
        if (locationSharing){
            locationButton.setImage(UIImage(named: "location_off"), for: UIControlState.normal)
            locationText.isHidden = true
            locationBg.isHidden = true
        } else {
            locationButton.setImage(UIImage(named: "location_on"), for: UIControlState.normal)
            locationText.isHidden = false
            locationBg.isHidden = false
        }
        locationSharing = !locationSharing
    }
    
    /**
     Toggles the text field to appear when the text button is pressed
     */
    @IBAction func toggleText(){
        self.caption.isHidden = !self.caption.isHidden
        if !self.caption.isHidden {
            self.caption.becomeFirstResponder()
        }
    }
    
    /**
     Starts the loading animation and begins the uploading process
     */
    @IBAction func uploadImage() {
        self.loading.startAnimating()
        self.loading.hidesWhenStopped = true
        // Only allows image to upload once a location has been retrieved
        if (userLocation?.placemark != nil){
            asyncUpload()
        } else {
            // Sets a flag to indicate the app is waiting for a retrieved location
            isWaitingForLocation = true
        }
    }
    
    // MARK: - Upload Functions
    
    /**
     Uploads a photo to the database using multipart form data
     */
    func asyncUpload(){
        let deviceID = UIDevice.current.identifierForVendor?.uuidString as String!
        let captionText = self.caption.text!
        let latitude : String = "\(self.userLocation!.location.coordinate.latitude)"
        let longitude : String = "\(self.userLocation!.location.coordinate.longitude)"
        if let image : UIImage = currentImage {
            if let data : Data = UIImageJPEGRepresentation(image, 0.0) {
                let base64 : String = data.base64EncodedString() // Image data to encoded string
                let stringData : Data = base64.data(using: String.Encoding.utf8)! as Data // String to Data
                Alamofire.upload(
                    multipartFormData: { multipartFormData in
                        multipartFormData.append(stringData, withName: "imageData")
                        multipartFormData.append("\(latitude)".data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"latitude")
                        multipartFormData.append("\(longitude)".data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"longitude")
                        multipartFormData.append("\(deviceID)".data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"deviceID")
                        multipartFormData.append(captionText.data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"caption")
                        multipartFormData.append("false".data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"favorite")
                },
                    to: "https://droplightapi.herokuapp.com/apiv1/upload",
                    encodingCompletion: { encodingResult in
                        switch encodingResult {
                        case .success(let upload, _, _):
                            upload.responseJSON { response in
                                let imageUrl = NSString(data: response.data!, encoding: String.Encoding.utf8.rawValue) as! String
                                print(imageUrl)
                                self.collectionImages?.addCard(card: Card(image: self.currentImage, imageUrl: imageUrl, caption: captionText, location: (self.userLocation?.location.coordinate)!, deviceID: deviceID!, favorite: false))
                                self.addToCollection(imageUrl: imageUrl, deviceID: deviceID!, caption: captionText, latitude: latitude, longitude: longitude, favorite: "false")
                                self.didUpload = true
                                self.loading.stopAnimating()
                                self.performSegue(withIdentifier: "UploadPicture", sender: self)
                            }
                        case .failure(let encodingError):
                            print(encodingError)
                        }
                }
                )
            }
        }
    }
    
    /**
     Sends an asynchronus call to the database to add an item to your collection when you upload a photo
     */
    func addToCollection(imageUrl: String, deviceID: String, caption: String, latitude: String, longitude: String, favorite: String){
        Alamofire.upload(
            multipartFormData: { multipartFormData in
                multipartFormData.append(imageUrl.data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"url")
                multipartFormData.append(latitude.data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"latitude")
                multipartFormData.append(longitude.data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"longitude")
                multipartFormData.append("\(deviceID)".data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"device")
                multipartFormData.append(caption.data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"caption")
                multipartFormData.append(favorite.data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName :"favorite")
        },
            to: "https://droplightapi.herokuapp.com/apiv1/favorites",
            encodingCompletion: { encodingResult in
                switch encodingResult {
                case .success(let upload, _, _):
                    upload.responseJSON { response in
                        print(NSString(data: response.data!, encoding: String.Encoding.utf8.rawValue) as! String)
                    }
                case .failure(let encodingError):
                    print(encodingError)
                }
        })
    }

    // MARK: - Keyboard Handling Functions
    
    /**
     Hides the keyboard when the background is pressed
     */
    func tapBackground(){
        if (caption.isHidden){
            toggleText()
        } else {
            self.view.endEditing(true)
        }
    }
    
    /**
     Registers for keyboard listeners when view controller is started
     */
    func registerForKeyboardNotifications(){
        captionBottom = self.caption.frame.minY
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWasShown(notification:)), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillBeHidden(notification:)), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    /**
     Deregisters from keyboard listeners when view controller is ending
     */
    func deregisterFromKeyboardNotifications(){
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    /**
     Brings text field to above the keyboard when a keyboard is created or changed
     */
    func keyboardWasShown(notification: NSNotification){
        var info = notification.userInfo!
        let keyboardSize = (info[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.origin.y
        self.caption.transform = self.caption.transform.translatedBy(x: 0, y: -1 * self.caption.frame.origin.y)
        UIView.animate(withDuration: 0.4, delay: 0, options: [UIViewAnimationOptions.curveEaseOut], animations: {
            self.caption.transform = self.caption.transform.translatedBy(x: 0, y: keyboardSize! - self.caption.frame.height)
        })
    }
    
    /**
     Hides the text field when 'Done' is pressed
     */
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tapBackground()
        return false
    }
    
    /**
     Sets text field to appear at bottom of screen when keyboard is about to be hidden
     */
    func keyboardWillBeHidden(notification: NSNotification){
        if self.caption.text == "" {
            toggleText()
        }
        self.caption.transform = self.caption.transform.translatedBy(x: 0, y: -1 * self.caption.frame.origin.y)
        UIView.animate(withDuration: 0.4, delay: 0, options: [UIViewAnimationOptions.curveEaseOut], animations: {
            self.caption.transform = self.caption.transform.translatedBy(x: 0, y: self.captionBottom)
        })
    }
    
    /**
     Limits characters to fit inside text field
     */
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard var text = textField.text as NSString? else { return true }
        text = text.replacingCharacters(in: range, with: string) as NSString
        let textSize : CGSize = text.size(attributes: [NSFontAttributeName: textField.font!])
        return (textSize.width < textField.bounds.size.width - 30) ? true : false;
    }
    
}
