import React, { useState } from 'react'

const AddButton = () => {
    
	const [isOpen, setIsOpen] = useState(false);
	
	const openDialog = () => setIsOpen(true);
	const closeDialog = () => setIsOpen(false);
	
	return (
		
		<> 
			<button className='add-button' onClick={openDialog}>
				Add Funds
			</button>
				
		{isOpen && (
			
			<div>
				<div className='background-overlay'></div>
				<div className='modal-dialog'>
					<form className = 'modal-contents' method='post' action='/balance'>
	   	 				<input type="hidden" name="authenticity_token" 
						value={document.querySelector("meta[name='csrf-token']")?.getAttribute("content")}/>
						<h2>Add Funds</h2>
						<div>
							<input type='number' placeholder='Amount' name='amount' min='0.01' step='0.01'/>
						</div>
						<div>
							<input type='submit' name='commit' value='add funds'/>
						</div>
					</form>
					<button className='close-button' onClick={closeDialog}>
						X
					</button>
				</div>
				</div>
		)}
			</>
	);
};

export default AddButton;
