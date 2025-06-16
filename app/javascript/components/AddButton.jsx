import React, { useState } from 'react'

const AddButton = () => {
    
	const [isSubmitting, setIsSubmitting] = useState(false);
	const [isOpen, setIsOpen] = useState(false);
	
	const openDialog = () => setIsOpen(true);
	const closeDialog = () => setIsOpen(false);
	const handleSubmit = () => {
	    setTimeout(() => setIsSubmitting(true), 10);
	};
	
	return (
		
		<> 
			<button className='add-withdraw-button' onClick={openDialog}>
				Add Funds
			</button>
				
		{isOpen && (
			
			<div>
				<div className='background-overlay'></div>
				<div className='modal-dialog'>
				<div className='modal-header'>
						<h2>Add Funds</h2>
				</div>
					<form className = 'modal-form' method='post' action='/balance' onSubmit={handleSubmit}>
	   	 				<input type="hidden" name="authenticity_token" 
						value={document.querySelector("meta[name='csrf-token']")?.getAttribute("content")}/>
						
						<div className='modal-amount'>
							<input type='number' placeholder='Amount' name='amount' min='0.01' step='0.01' className='shares-input'/>
						</div>
						<div className='modal-submit'>
							<button type='submit' name='commit' value='add' className='aw-submit' disabled={isSubmitting}>
                            {isSubmitting ? 'Processing...' : 'Submit'}
							</button>
						</div>
			
					</form>
			
					<button className='close-button' onClick={closeDialog} disabled={isSubmitting}>
						X
					</button>
			
				</div>
				</div>
		)}
			</>
	);
};

export default AddButton;
